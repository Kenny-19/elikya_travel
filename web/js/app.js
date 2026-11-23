/* app.js — boot : authentification, sidebar, routage des modules */
(function(){
  var loginView = document.getElementById('loginView');
  var appView   = document.getElementById('appView');
  var GROUPS = ['Pilotage','Activités','Référentiel','Système'];

  // ----- config manquante -----
  if(!Elikya.configOk){
    var m = document.getElementById('loginMsg');
    if(m){ m.className='msg err'; m.textContent="Configuration manquante : copie config.example.js en config.js et colle ta clé anon."; }
  }

  // ----- Auth -----
  var form = document.getElementById('loginForm');
  if(form) form.addEventListener('submit', async function(e){
    e.preventDefault();
    if(!Elikya.db) return;
    var btn=document.getElementById('loginBtn'), msg=document.getElementById('loginMsg');
    if(navigator.onLine===false){ msg.className='msg err'; msg.textContent="Pas de connexion internet : impossible de se connecter."; return; }
    btn.disabled=true; btn.textContent="Connexion…"; msg.textContent="";
    var res = await Elikya.db.auth.signInWithPassword({
      email: document.getElementById('email').value.trim(),
      password: document.getElementById('password').value
    });
    btn.disabled=false; btn.textContent="Se connecter";
    if(res.error){ msg.className='msg err'; msg.textContent="Échec : "+res.error.message; return; }
    boot();
  });

  var logout = document.getElementById('logout');
  if(logout) logout.addEventListener('click', async function(){
    if(Elikya.db) await Elikya.db.auth.signOut();
    location.hash=''; location.reload();
  });

  // ----- Sidebar -----
  function buildSidebar(){
    var nav = document.getElementById('nav');
    var html = '';
    GROUPS.forEach(function(g){
      // les modules « cachés » (ex. admin) n'apparaissent jamais dans le menu
      var items = Elikya.modules.filter(function(m){ return (m.group||'Activités')===g && !m.hidden; });
      if(!items.length) return;
      html += '<div class="grp">'+g+'</div>';
      items.forEach(function(m){
        html += '<a data-mod="'+m.id+'">'+m.label+(m.soon?' <span class="tag">bientôt</span>':'')+'</a>';
      });
    });
    nav.innerHTML = html;
    nav.addEventListener('click', function(e){
      var a = e.target.closest('a[data-mod]'); if(!a) return;
      e.preventDefault(); route(a.dataset.mod);
    });
  }

  function route(id){
    var m = Elikya.getModule(id);
    if(!m || (m.superAdmin && !Elikya.superAdmin)) m = Elikya.modules[0];   // #admin sans droit → accueil
    if(!m) return;
    current = m.id;
    document.querySelectorAll('#nav a').forEach(function(a){ a.classList.toggle('on', a.dataset.mod===m.id); });
    try{ if(location.hash.slice(1)!==m.id) history.replaceState(null,'','#'+m.id); }catch(e){}
    var root = document.getElementById('moduleRoot');
    root.innerHTML = '';
    Promise.resolve(m.render(root)).catch(function(err){
      root.innerHTML = '<div class="card"><p style="color:var(--crit)">Erreur module : '+err.message+'</p></div>';
    });
  }

  // ----- Entrée cachée du super admin -----
  // Ctrl+Maj+A, ou 5 clics rapides sur le logo de la barre latérale, ou l'adresse …/#admin.
  // (Uniquement pour un compte super admin ; pour les autres, rien ne se passe.)
  function installSecretEntry(){
    if(installSecretEntry.done) return;
    installSecretEntry.done = true;
    document.addEventListener('keydown', function(e){
      if(e.ctrlKey && e.shiftKey && (e.key === 'A' || e.key === 'a')){ e.preventDefault(); route('admin'); }
    });
    var clics = 0, t = null, logo = document.querySelector('.side .brand');
    if(logo) logo.addEventListener('click', function(){
      clics++; clearTimeout(t); t = setTimeout(function(){ clics = 0; }, 1500);
      if(clics >= 5){ clics = 0; route('admin'); }
    });
    var foot = document.getElementById('whoMail');
    if(foot) foot.insertAdjacentHTML('afterend', '<span class="sa-badge" title="Entrée administration : Ctrl+Maj+A">Super admin</span>');
  }

  // ----- Bandeau réseau (en ligne prioritaire / local en secours) -----
  var current = null;
  window.addEventListener('elikya:data', function(e){
    var d = e.detail, bar = document.getElementById('netBar');
    if(!bar) return;
    var html = '';
    if(!d.online){
      html = '<b>Hors ligne</b> — base en ligne injoignable. Les saisies sont gardées sur ce poste'+
        (d.pending ? ' (<b>'+d.pending+'</b> en attente)' : '')+' et seront envoyées au retour du réseau.';
    } else if(d.pending){
      html = 'Synchronisation en cours… <b>'+d.pending+'</b> saisie(s) à envoyer.';
    }
    if(d.failed){
      html += (html?' · ':'')+'<b>'+d.failed+'</b> saisie(s) refusée(s) par la base en ligne '+
        '<button class="lnk" id="failedBtn">voir</button>';
    }
    bar.innerHTML = html;
    bar.className = 'netbar' + (html ? (d.online ? ' info' : '') : ' hidden');
    var fb = document.getElementById('failedBtn');
    if(fb) fb.onclick = showFailed;
    if(d.synced && d.online){
      Elikya.h.toast('Connexion rétablie · données synchronisées ✓');
      if(current) route(current);   // relit le module depuis la base en ligne
    }
  });

  async function showFailed(){
    var items = await Elikya.data.failedItems();
    var txt = items.map(function(it){
      return '• '+it.table+' ('+it.op+', '+(it.at||'').slice(0,16).replace('T',' ')+') : '+it.error;
    }).join('\n');
    if(confirm('Saisies refusées par la base en ligne :\n\n'+txt+'\n\nOK = effacer cette liste (après les avoir ressaisies si besoin).')){
      Elikya.data.clearFailed();
    }
  }

  // Session : lue localement (marche hors ligne si le poste s'est déjà connecté une fois)
  async function currentUser(){
    try{
      var s = await Elikya.db.auth.getSession();
      var u = s.data && s.data.session && s.data.session.user;
      if(u) return u;
    }catch(e){}
    if(Elikya.data.status().online) return null;
    // hors ligne et jeton expiré : on garde l'identité mémorisée pour pouvoir saisir
    try{
      for(var i=0;i<localStorage.length;i++){
        var k = localStorage.key(i);
        if(/^sb-.*-auth-token$/.test(k)){
          var v = JSON.parse(localStorage.getItem(k));
          if(v && v.user) return v.user;
        }
      }
    }catch(e){}
    return null;
  }

  // ----- Profil / rôle -----
  var PROFILE_KEY = 'elikya-profil';
  async function loadProfile(){
    var r;
    try{ r = await Elikya.db.rpc('mon_profil'); }catch(e){ r = { error:e }; }
    if(r && !r.error){
      var p = r.data;
      if(!p) return { denied:true, message:"Ce compte n'est relié à aucune fiche employé active. Demande à la direction de l'ajouter dans la table users (même e-mail)." };
      if(!(p.permissions && p.permissions.all === true))
        return { denied:true, message:"Ce site est réservé à la direction. Les agents utilisent l'application bureau Elikya Agents." };
      try{ localStorage.setItem(PROFILE_KEY, JSON.stringify(p)); }catch(e){}
      return { data:p };
    }
    var msg = String((r && r.error && (r.error.message || r.error)) || '');
    if(/mon_profil|PGRST202|function/i.test(msg) && !/fetch|network/i.test(msg))
      return { denied:true, message:"Rôles non installés : exécute db/roles.sql dans Supabase (SQL Editor)." };
    // réseau coupé : on se fie au dernier profil direction connu sur ce poste
    try{
      var c = JSON.parse(localStorage.getItem(PROFILE_KEY)||'null');
      if(c && c.permissions && c.permissions.all === true) return { data:c };
    }catch(e){}
    return { denied:true, message:"Impossible de vérifier le compte (pas de connexion). Réessaie avec internet." };
  }

  function denyAccess(message){
    appView.classList.add('hidden'); loginView.classList.remove('hidden');
    var m = document.getElementById('loginMsg');
    m.className = 'msg err'; m.textContent = message;
    try{ localStorage.removeItem(PROFILE_KEY); }catch(e){}
    Elikya.db.auth.signOut();
  }

  // ----- Boot -----
  async function boot(){
    if(!Elikya.db){ return; }
    var user = await currentUser();
    if(!user){
      loginView.classList.remove('hidden'); appView.classList.add('hidden');
      if(!Elikya.data.status().online){
        var m = document.getElementById('loginMsg');
        m.className='msg err'; m.textContent="Hors ligne : la première connexion d'un poste doit se faire avec internet.";
      }
      return;
    }
    Elikya.user = user;

    // Site propriétaire : réservé à la direction (rôle avec permissions.all, cf. db/roles.sql).
    // Les agents utilisent l'application bureau Flutter (agents/).
    var prof = await loadProfile();
    if(prof.denied){ return denyAccess(prof.message); }
    Elikya.profile = prof.data;

    // Super administrateur (db/superadmin.sql : rôle avec permissions.admin) : entrée cachée
    // #admin (comptes, rôles) et saisie réactivée. La vraie protection est côté base (RLS)
    // et côté fonction serveur admin-comptes, pas dans le fait que l'entrée soit cachée.
    Elikya.superAdmin = !!(prof.data && prof.data.permissions && prof.data.permissions.admin === true);

    // Site direction = CONSULTATION : aucune saisie (les agents saisissent dans l'app Flutter).
    // Les contrôles marqués data-ecriture sont masqués (styles.css) et Elikya.data refuse
    // toute écriture. Seul le super admin garde la saisie.
    Elikya.readOnly = !Elikya.superAdmin;
    document.body.classList.toggle('lecture-seule', Elikya.readOnly);
    document.body.classList.toggle('super-admin', Elikya.superAdmin);

    loginView.classList.add('hidden'); appView.classList.remove('hidden');
    document.getElementById('whoMail').textContent = (prof.data && prof.data.role) || user.email;
    document.getElementById('whoName').textContent = (prof.data && prof.data.nom) || (user.email||'').split('@')[0];
    document.getElementById('avatar').textContent = ((prof.data && prof.data.nom) || user.email || '?').slice(0,2).toUpperCase();
    buildSidebar();
    if(Elikya.superAdmin) installSecretEntry();
    var start = (location.hash.slice(1)) || (Elikya.modules[0] && Elikya.modules[0].id);
    route(start);
    // envoie ce qui attend sur le poste, puis rafraîchit la copie locale en arrière-plan
    Elikya.data.sync().then(Elikya.data.warmup);
  }

  boot();
})();
