/* data.js — couche d'accès aux données unique : Elikya.data
   Règle : Supabase EN LIGNE est PRIORITAIRE. La base LOCALE (IndexedDB) ne sert que
   si Supabase est inaccessible :
     - chaque lecture en ligne réussie met à jour la copie locale ;
     - hors ligne : lectures depuis la copie locale, écritures mises en file (outbox) ;
     - au retour du réseau : la file est rejouée dans l'ordre (upsert sur l'id → pas de doublon).
   API (toutes renvoient { data, error, offline }) :
     Elikya.data.select(table, { embed:['clients(nom)'], eq:{col:v}, gte:{col:v}, lte:{col:v},
                                 order:['col', asc?], limit:n, single:bool })
     Elikya.data.insert(table, row)          → row complète (id généré côté poste)
     Elikya.data.update(table, id, patch)
   Événement window 'elikya:data' (detail: {online, pending, failed, synced}) à chaque changement. */
(function(){
  var E = window.Elikya;
  var DB_NAME = 'elikya-local';
  var DB_VERSION = 1;           // ⚠ incrémenter si on ajoute une table à TABLES
  var TIMEOUT_MS = 8000;        // au-delà, on considère Supabase injoignable
  var PROBE_MS = 15000;         // test de reconnexion quand hors ligne
  var WARM_LIMIT = 1000;        // lignes récentes copiées par table au démarrage

  // Tables copiées en local. rels : alias embarqué → [table cible, clé étrangère]
  // ts : la table a une colonne cree_le (renseignée côté poste à la création).
  var TABLES = {
    roles:             {},
    devises:           {},
    users:             { rels:{ roles:['roles','role_id'] } },
    clients:           { ts:true, rels:{ users:['users','cree_par'] } },
    produits:          {},
    dossiers:          { ts:true, rels:{ clients:['clients','client_id'], devises:['devises','devise_id'], users:['users','agent_id'] } },
    commandes:         { ts:true, rels:{ clients:['clients','client_id'] } },
    commande_lignes:   { rels:{ produits:['produits','produit_id'], commandes:['commandes','commande_id'] } },
    momo_comptes:      {},
    momo_transactions: { ts:true, rels:{ momo_comptes:['momo_comptes','compte_id'], users:['users','agent_id'] } },
    caisse_sessions:   { order:'jour', rels:{ users:['users','agent_id'] } },
    paiements:         { ts:true, rels:{ devises:['devises','devise_id'], users:['users','recu_par'] } },
    mouvements_caisse: { ts:true, rels:{ devises:['devises','devise_id'], caisse_sessions:['caisse_sessions','session_id'], users:['users','agent_id'] } },
    parametres:        { key:'cle' }
  };
  function keyOf(t){ return (TABLES[t] && TABLES[t].key) || 'id'; }

  // ---------------------------------------------------------------- IndexedDB
  var ready = new Promise(function(resolve){
    try{
      if(!window.indexedDB) return resolve(null);
      var r = indexedDB.open(DB_NAME, DB_VERSION);
      r.onupgradeneeded = function(){
        var d = r.result;
        Object.keys(TABLES).forEach(function(t){
          if(!d.objectStoreNames.contains(t)) d.createObjectStore(t, { keyPath:keyOf(t) });
        });
        ['outbox','failed'].forEach(function(s){
          if(!d.objectStoreNames.contains(s)) d.createObjectStore(s, { keyPath:'seq', autoIncrement:true });
        });
      };
      r.onsuccess = function(){ resolve(r.result); };
      r.onerror = function(){ console.warn('IndexedDB indisponible', r.error); resolve(null); };
    }catch(e){ console.warn('IndexedDB indisponible', e); resolve(null); }
  });

  function tx(store, mode, fn){
    return ready.then(function(d){
      if(!d) return null;
      return new Promise(function(res, rej){
        var t = d.transaction(store, mode), out = fn(t.objectStore(store));
        t.oncomplete = function(){ res(out && 'result' in out ? out.result : undefined); };
        t.onerror = t.onabort = function(){ rej(t.error); };
      });
    });
  }
  function getAll(store){ return tx(store,'readonly',function(s){ return s.getAll(); }).then(function(r){ return r||[]; }); }
  function getOne(store, k){ return tx(store,'readonly',function(s){ return s.get(k); }); }
  function putMany(store, rows){ if(!rows.length) return Promise.resolve(); return tx(store,'readwrite',function(s){ rows.forEach(function(r){ s.put(r); }); }); }
  function addOne(store, v){ return tx(store,'readwrite',function(s){ return s.add(v); }); }
  function delOne(store, k){ return tx(store,'readwrite',function(s){ return s.delete(k); }); }
  function count(store){ return tx(store,'readonly',function(s){ return s.count(); }).then(function(n){ return n||0; }); }

  // retire les objets embarqués (clients(nom)…) avant stockage local
  function strip(table, row){
    var rels = (TABLES[table] && TABLES[table].rels) || {}, o = {};
    Object.keys(row).forEach(function(k){ if(!(rels[k] || TABLES[k])) o[k] = row[k]; });
    return o;
  }
  function cache(table, rows){
    if(!TABLES[table] || !rows || !rows.length) return Promise.resolve();
    return putMany(table, rows.map(function(r){ return strip(table, r); })).catch(function(e){ console.warn('cache', table, e); });
  }

  function uuid(){
    if(window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16); crypto.getRandomValues(b);
    b[6] = (b[6]&15)|64; b[8] = (b[8]&63)|128;
    var x = Array.prototype.map.call(b, function(v){ return (v+256).toString(16).slice(1); }).join('');
    return x.slice(0,8)+'-'+x.slice(8,12)+'-'+x.slice(12,16)+'-'+x.slice(16,20)+'-'+x.slice(20);
  }

  // ---------------------------------------------------------------- réseau
  var state = { online: navigator.onLine !== false, pending:0, failed:0, syncing:false };
  var probeTimer = null;

  function emit(extra){
    window.dispatchEvent(new CustomEvent('elikya:data', { detail: Object.assign({
      online:state.online, pending:state.pending, failed:state.failed }, extra||{}) }));
  }
  function isNetErr(err){
    if(!err) return false;
    if(navigator.onLine === false) return true;
    var m = String((err && (err.message || err.details)) || err);
    return err.code === 'ETIMEOUT' || /failed to fetch|fetch failed|networkerror|network request|load failed|timeout/i.test(m);
  }
  // exécute une requête supabase ; { net:true } si Supabase est injoignable
  function run(builder){
    var timer;
    var timeout = new Promise(function(_, rej){ timer = setTimeout(function(){ rej({ message:'timeout', code:'ETIMEOUT' }); }, TIMEOUT_MS); });
    return Promise.race([Promise.resolve(builder), timeout]).then(function(r){
      clearTimeout(timer);
      if(r && r.error && isNetErr(r.error)) return { net:true, error:r.error };
      return r || {};
    }, function(e){
      clearTimeout(timer);
      return { net:true, error:e };
    });
  }

  function goOffline(){
    if(state.online){ state.online = false; emit(); }
    if(!probeTimer) probeTimer = setInterval(probe, PROBE_MS);
  }
  async function goOnline(){
    if(probeTimer){ clearInterval(probeTimer); probeTimer = null; }
    var was = state.online;
    state.online = true;
    var hadPending = state.pending > 0;
    await sync();
    if(state.online) emit({ synced: !was || hadPending });
  }
  async function probe(){
    if(!E.db) return;
    var r = await run(E.db.from('devises').select('id').limit(1));
    if(!r.net) goOnline();
  }
  window.addEventListener('online', probe);
  window.addEventListener('offline', goOffline);

  // ---------------------------------------------------------------- lecture
  function each(obj, fn){ if(obj) Object.keys(obj).forEach(function(k){ fn(k, obj[k]); }); }
  function cmp(a, b){
    if(a === b) return 0;
    if(a == null) return 1;
    if(b == null) return -1;
    if(typeof a === 'number' && typeof b === 'number') return a - b;
    a = String(a); b = String(b);
    return a < b ? -1 : a > b ? 1 : 0;
  }

  async function select(table, o){
    o = o || {};
    if(state.online && E.db){
      var q = E.db.from(table).select(['*'].concat(o.embed||[]).join(','));
      each(o.eq,  function(k,v){ q = q.eq(k, v); });
      each(o.gte, function(k,v){ q = q.gte(k, v); });
      each(o.lte, function(k,v){ q = q.lte(k, v); });
      if(o.order) q = q.order(o.order[0], { ascending: o.order[1] !== false });
      if(o.limit) q = q.limit(o.limit);
      var r = await run(q);
      if(!r.net){
        if(!r.error) cache(table, r.data||[]);
        var rows = r.data || [];
        return { data: o.single ? (rows[0]||null) : rows, error: r.error||null, offline:false };
      }
      goOffline();
    }
    return localSelect(table, o);
  }

  async function localSelect(table, o){
    if(!(await ready)) return { data: o.single?null:[], error:{ message:'Hors ligne : aucune copie locale disponible sur ce poste.' }, offline:true };
    var rows = (await getAll(table)).filter(function(r){
      var ok = true;
      each(o.eq,  function(k,v){ if(String(r[k]) !== String(v)) ok = false; });
      each(o.gte, function(k,v){ if(r[k] == null || cmp(r[k], v) < 0) ok = false; });
      each(o.lte, function(k,v){ if(r[k] == null || cmp(r[k], v) > 0) ok = false; });
      return ok;
    });
    if(o.order){
      var c = o.order[0], dir = o.order[1] === false ? -1 : 1;
      rows.sort(function(a, b){ return cmp(a[c], b[c]) * dir; });
    }
    if(o.limit) rows = rows.slice(0, o.limit);
    rows = await embedLocal(table, rows, o.embed||[]);
    return { data: o.single ? (rows[0]||null) : rows, error:null, offline:true };
  }

  async function embedLocal(table, rows, specs){
    var rels = (TABLES[table] && TABLES[table].rels) || {};
    for(var i=0; i<specs.length; i++){
      var m = /^(\w+)\((.*)\)$/.exec(specs[i].replace(/\s/g,''));
      if(!m || !rels[m[1]]) continue;
      var alias = m[1], target = rels[alias][0], fk = rels[alias][1];
      var fields = m[2] === '*' ? null : m[2].split(',');
      var byKey = {};
      (await getAll(target)).forEach(function(x){ byKey[String(x[keyOf(target)])] = x; });
      rows.forEach(function(r){
        var t = r[fk] == null ? null : byKey[String(r[fk])];
        if(!t){ r[alias] = null; return; }
        if(!fields){ r[alias] = t; return; }
        var p = {}; fields.forEach(function(f){ p[f] = t[f]; }); r[alias] = p;
      });
    }
    return rows;
  }

  // ---------------------------------------------------------------- écriture
  async function queue(item){
    item.at = new Date().toISOString();
    await addOne('outbox', item);
    await refreshCounts();
  }

  async function insert(table, row){
    row = Object.assign({}, row);
    var k = keyOf(table);
    if(row[k] == null && k === 'id') row.id = uuid();
    if(TABLES[table] && TABLES[table].ts && !row.cree_le) row.cree_le = new Date().toISOString();
    if(state.online && E.db){
      var r = await run(E.db.from(table).insert(row).select());
      if(!r.net){
        var saved = (r.data && r.data[0]) || null;
        if(!r.error && saved) cache(table, [saved]);
        return { data: r.error ? null : (saved || row), error: r.error||null, offline:false };
      }
      goOffline();
    }
    if(!(await ready)) return { data:null, error:{ message:'Hors ligne et stockage local indisponible : saisie non enregistrée.' }, offline:true };
    await cache(table, [row]);
    await queue({ op:'insert', table:table, row:row });
    return { data:row, error:null, offline:true };
  }

  async function update(table, id, patch){
    var k = keyOf(table);
    if(state.online && E.db){
      var r = await run(E.db.from(table).update(patch).eq(k, id).select());
      if(!r.net){
        var saved = (r.data && r.data[0]) || null;
        if(!r.error && saved) cache(table, [saved]);
        return { data:saved, error:r.error||null, offline:false };
      }
      goOffline();
    }
    if(!(await ready)) return { data:null, error:{ message:'Hors ligne et stockage local indisponible : modification non enregistrée.' }, offline:true };
    var cur = await getOne(table, id);
    var merged = Object.assign({}, cur||{}, patch); merged[k] = id;
    await cache(table, [merged]);
    await queue({ op:'update', table:table, id:id, patch:patch });
    return { data:merged, error:null, offline:true };
  }

  // ---------------------------------------------------------------- synchro
  async function refreshCounts(){
    if(!(await ready)) return;
    state.pending = await count('outbox');
    state.failed = await count('failed');
    emit();
  }

  async function sync(){
    if(state.syncing || !E.db || !(await ready)) return;
    state.syncing = true;
    try{
      var items = (await getAll('outbox')).sort(function(a,b){ return a.seq - b.seq; });
      for(var i=0; i<items.length; i++){
        var it = items[i], k = keyOf(it.table);
        var b = it.op === 'insert'
          ? E.db.from(it.table).upsert(it.row, { onConflict:k })
          : E.db.from(it.table).update(it.patch).eq(k, it.id);
        var r = await run(b);
        if(r.net){ goOffline(); break; }
        if(r.error){
          // refusé par la base (contrainte…) : on le met de côté pour que quelqu'un le voie
          var f = Object.assign({}, it, { error:r.error.message, code:r.error.code||'' }); delete f.seq;
          await addOne('failed', f);
          if(it.op === 'insert') await delOne(it.table, it.row[k]).catch(function(){});
        }
        await delOne('outbox', it.seq);
      }
    } finally {
      state.syncing = false;
      await refreshCounts();
    }
  }

  // copie locale des données récentes, pour être prêt en cas de coupure
  async function warmup(){
    if(!state.online || !E.db || !(await ready)) return;
    var names = Object.keys(TABLES);
    for(var i=0; i<names.length && state.online; i++){
      var t = names[i], cfg = TABLES[t];
      var ord = cfg.order || (cfg.ts ? 'cree_le' : null);
      await select(t, { order: ord ? [ord, false] : null, limit: WARM_LIMIT });
    }
  }

  async function failedItems(){ return (await ready) ? getAll('failed') : []; }
  async function clearFailed(){ if(await ready){ await tx('failed','readwrite',function(s){ s.clear(); }); await refreshCounts(); } }

  E.data = {
    select: select, insert: insert, update: update,
    sync: sync, warmup: warmup, probe: probe,
    failedItems: failedItems, clearFailed: clearFailed,
    status: function(){ return { online:state.online, pending:state.pending, failed:state.failed }; },
    goOffline: goOffline
  };
  refreshCounts();
  if(!state.online) goOffline();
})();
