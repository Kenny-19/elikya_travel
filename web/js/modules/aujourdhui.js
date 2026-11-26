/* modules/aujourdhui.js — « Aujourd'hui » : la vue globale de la direction, d'un coup d'œil.
   Page d'accueil du site (lecture seule), pensée pour le téléphone comme pour l'ordinateur :
     1. ventes du jour (toutes activités) + comparaison avec hier, une tuile cliquable par activité ;
     2. à traiter (alertes) ;
     3. la caisse de chaque agent (ouverte / fermée avec écart / oubliée / pas ouverte) ;
     4. qui a fait quoi aujourd'hui (fil d'activité, filtrable par agent).
   Calculs dans js/stats.js (testés). Montants en USD (CDF converti au taux). Rafraîchi toutes les 2 minutes. */
Elikya.registerModule({
  id: 'aujourdhui',
  label: 'Aujourd’hui',
  group: 'Pilotage',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var agentFiltre = '', fil = [], timer = null;
    var ACTIVITES = [
      { mod:'Voyage', titre:'Voyage', lien:'voyage', unite:['dossier','dossiers'] },
      { mod:'Location', titre:'Location', lien:'location', unite:['location','locations'] },
      { mod:'Fourniture', titre:'Fourniture', lien:'fourniture', unite:['commande','commandes'] },
      { mod:'Mobile Money', titre:'Mobile money', lien:'momo', unite:['opération','opérations'] }
    ];
    var ETAT_CAISSE = {
      ouverte:['Ouverte','ok'], fermee:['Fermée','neutral'], oubliee:['Pas fermée','warn'], pas_ouverte:['Pas ouverte','neutral']
    };

    function usd(n){ return h.money(Math.round((n||0)*100)/100, 'USD'); }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function pl(n, u){ return n+' '+(n > 1 ? u[1] : u[0]); }
    function heure(iso){ var d = new Date(iso); return isNaN(d) ? '' : d.toLocaleTimeString('fr-FR', { hour:'2-digit', minute:'2-digit' }); }

    var dateLongue = new Date().toLocaleDateString('fr-FR', { weekday:'long', day:'numeric', month:'long', year:'numeric' });
    var prenom = ((Elikya.profile && Elikya.profile.nom) || '').trim().split(/\s+/)[0];

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Vue globale · '+esc(dateLongue)+'</div>'+
        '<h1 class="pf">'+(prenom ? 'Bonjour '+esc(prenom) : 'Aujourd’hui')+'</h1>'+
        '<p>Tout ce qui se passe aujourd’hui chez Elikya Group, en un coup d’œil.</p></div>'+
        '<div class="toolbar" style="margin:0"><span class="maj" id="maj"></span><button class="btn" id="refreshBtn">↻ Actualiser</button></div></div>'+
      '<div class="auj-hero card" id="hero"><span class="spin"></span></div>'+
      '<div class="auj-acts" id="acts"></div>'+
      '<div class="grid2 auj-grid">'+
        '<div class="card"><h3>À traiter</h3><ul class="alerts" id="alerts"><li><span class="spin"></span></li></ul></div>'+
        '<div class="card"><h3>Caisses des agents</h3><div id="caisses"><span class="spin"></span></div></div>'+
      '</div>'+
      '<div class="card"><div class="auj-filhead"><h3>Qui a fait quoi aujourd’hui</h3><div class="chips" id="chips"></div></div>'+
        '<ul class="auj-fil" id="fil"><li><span class="spin"></span></li></ul></div>';

    function renderFil(){
      var list = agentFiltre ? fil.filter(function(e){ return e.agent === agentFiltre; }) : fil;
      $('#fil').innerHTML = list.length ? list.map(function(e){
        var m = e.montant == null ? '' : (e.signe > 0 ? '+ ' : e.signe < 0 ? '− ' : '')+usd(e.montant);
        var cls = e.signe > 0 ? 'in' : e.signe < 0 ? 'out' : '';
        var etat = e.etat === 'en_attente' ? ' '+h.pill('En attente', 'warn') : e.etat === 'echec' ? ' '+h.pill('Échec', 'crit')
          : e.etat === 'annule' ? ' '+h.pill('Annulé', 'crit') : '';
        return '<li><span class="t tnum">'+heure(e.quand)+'</span>'+
          '<div class="x"><b>'+esc(e.texte)+'</b>'+etat+
          '<span class="mod">'+esc(e.module)+(e.agent ? ' · '+esc(e.agent) : '')+'</span></div>'+
          '<span class="m tnum '+cls+'">'+m+'</span></li>';
      }).join('') : '<li class="vide">Rien de noté pour l’instant aujourd’hui.</li>';
    }

    async function load(){
      var now = new Date(), today = S.dayKey(now), hier = S.dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate()-1));
      var depuisHier = { gte:{ cree_le: new Date(now.getFullYear(), now.getMonth(), now.getDate()-1).toISOString() } };
      var il30j = S.dayKey(new Date(now.getTime() - 30*864e5));
      var r = await Promise.all([
        store.select('devises', {}),                                                              // 0
        store.select('dossiers', Object.assign({ embed:['clients(nom)'] }, depuisHier)),          // 1
        store.select('commandes', Object.assign({ embed:['clients(nom)'] }, depuisHier)),         // 2
        store.select('locations', Object.assign({ embed:['clients(nom)'] }, depuisHier)),         // 3
        store.select('momo_transactions', Object.assign({ embed:['momo_comptes(operateur)'] }, depuisHier)), // 4
        store.select('paiements', depuisHier),                                                    // 5
        store.select('caisse_sessions', { embed:['users(nom)'], gte:{ jour: il30j }, order:['jour', false] }), // 6
        store.select('users', {}),                                                                // 7
        store.select('produits', {}),                                                             // 8
        // états en cours, quelle que soit la date (alertes)
        store.select('momo_transactions', { eq:{ statut:'en_attente' } }),                        // 9
        store.select('commandes', { eq:{ statut:'a_livrer' } }),                                  // 10
        store.select('dossiers', { eq:{ statut:'devis' } }),                                      // 11
        store.select('dossiers', { embed:['clients(nom)'], gte:{ date_depart: today }, lte:{ date_depart: S.dayKey(new Date(now.getTime() + 3*864e5)) } }), // 12
        store.select('locations', { eq:{ statut:'en_cours' } }),                                  // 13
        store.select('paiements', { eq:{ source_type:'dossier' }, limit:3000 }),                  // 14
        store.select('caisse_sessions', { embed:['users(nom)'], eq:{ statut:'ouverte' } })        // 15 : anciennes restées ouvertes
      ]);
      var mv = await store.select('mouvements_caisse', { gte:{ cree_le: new Date(il30j+'T00:00:00').toISOString() } });
      if(!$('#hero')) return;   // on a changé d'écran pendant le chargement
      var err = r.concat([mv]).filter(function(x){ return x.error; })[0];
      var devises = r[0].data||[], users = r[7].data||[], mouvements = mv.data||[];
      var vus = {}, sessions = (r[6].data||[]).concat(r[15].data||[]).filter(function(s){ return vus[s.id] ? false : (vus[s.id] = true); });

      // ---- 1. ventes du jour ----
      var src = { devises:devises, dossiers:r[1].data||[], commandes:r[2].data||[], locations:r[3].data||[], momo_transactions:r[4].data||[] };
      var entries = S.journal(src);
      var j = S.totals(entries, new Date(today+'T00:00:00'), new Date(today+'T00:00:00'));
      var hh = S.totals(entries, new Date(hier+'T00:00:00'), new Date(hier+'T00:00:00'));
      var ventes = j['Voyage'] + j['Location'] + j['Fourniture'], ventesHier = hh['Voyage'] + hh['Location'] + hh['Fourniture'];
      var d = S.delta(ventes, ventesHier);
      var cmp = d === null ? 'Hier : rien de vendu' : d === 0 ? 'Comme hier ('+usd(ventesHier)+')'
        : (d > 0 ? '▲ +' : '▼ ')+d+' % par rapport à hier ('+usd(ventesHier)+')';
      var cz = S.caissesAgents({ devises:devises, users:users, caisse_sessions:sessions, mouvements_caisse:mouvements }, today);
      var enCaisses = cz.filter(function(c){ return c.etat === 'ouverte' || c.etat === 'oubliee'; })
        .reduce(function(a, c){ return a + c.enCaisse; }, 0);
      $('#hero').innerHTML =
        '<div><div class="lab">Ventes d’aujourd’hui</div><div class="big tnum">'+usd(ventes)+'</div>'+
          '<div class="delta '+(d > 0 ? 'up' : d < 0 ? 'down' : '')+'">'+cmp+'</div>'+
          '<div class="sub">Voyage, location et fourniture. Le mobile money est à part (volume).</div></div>'+
        '<div class="auj-hero2"><div><div class="lab">Argent dans les caisses</div><div class="mid tnum">'+usd(enCaisses)+'</div></div>'+
          '<div><div class="lab">Commissions mobile money</div><div class="mid tnum">'+usd(j.frais)+'</div></div></div>';

      $('#acts').innerHTML = ACTIVITES.map(function(a){
        var n = j.nb[a.mod], v = j[a.mod];
        return '<a class="card auj-act" href="#'+a.lien+'"><div class="lab">'+a.titre+(a.mod === 'Mobile Money' ? ' (volume)' : '')+'</div>'+
          '<div class="val tnum">'+usd(v)+'</div><div class="sub">'+(n ? pl(n, a.unite) : 'Rien aujourd’hui')+'</div>'+
          '<span class="go">Voir le détail →</span></a>';
      }).join('');

      // ---- 2. à traiter ----
      var al = S.alertes({
        devises:devises, produits:r[8].data||[], caisse_sessions:sessions, mouvements_caisse:mouvements,
        momo_transactions: (r[9].data||[]).concat((r[4].data||[]).filter(function(t){ return t.statut === 'echec' && S.dayKey(t.cree_le) === today; })),
        commandes: r[10].data||[], dossiers: r[11].data||[], departs: r[12].data||[], paiements: r[14].data||[], locations: r[13].data||[]
      }, now);
      var ICON = { crit:['Urgent','crit'], warn:['À voir','warn'], info:['Info','info'] };
      var LIEN = { 'Voyage':'voyage', 'Location':'location', 'Fourniture':'fourniture', 'Mobile Money':'momo', 'Caisse':'caisse' };
      $('#alerts').innerHTML = al.length ? al.slice(0, 8).map(function(a){
        return '<li>'+h.pill(ICON[a.niveau][0], ICON[a.niveau][1])+'<div>'+esc(a.texte)+
          '<a class="mod" href="#'+(LIEN[a.module]||'dashboard')+'">'+esc(a.module)+' →</a></div></li>';
      }).join('')+(al.length > 8 ? '<li><a href="#dashboard" class="mod">Voir les '+al.length+' points dans le tableau de bord →</a></li>' : '')
        : '<li class="vide">Rien à signaler ✓</li>';

      // ---- 3. caisses des agents ----
      $('#caisses').innerHTML = cz.length ? '<ul class="auj-caisses">'+cz.map(function(c){
        var e = ETAT_CAISSE[c.etat], detail;
        if(c.etat === 'ouverte') detail = 'Reçu '+usd(c.entrees)+' · sorti '+usd(c.sorties);
        else if(c.etat === 'fermee') detail = c.ecart == null ? 'Fermée' : Math.abs(c.ecart) < 0.01 ? 'Compte juste ✓'
          : (c.ecart < 0 ? 'Il manquait ' : 'Il y avait en trop ')+usd(Math.abs(c.ecart));
        else if(c.etat === 'oubliee') detail = 'Caisse du '+S.frDate(c.jour)+' jamais fermée';
        else detail = 'Pas encore ouverte aujourd’hui';
        var alerte = c.etat === 'oubliee' || (c.ecart != null && c.ecart < -0.004);
        return '<li><div class="av">'+esc((c.nom||'?').trim().charAt(0).toUpperCase())+'</div>'+
          '<div class="x"><b>'+esc(c.nom)+'</b> '+h.pill(e[0], e[1])+
          '<span class="mod'+(alerte ? ' crit' : '')+'">'+detail+'</span></div>'+
          '<span class="m tnum">'+(c.etat === 'pas_ouverte' ? '—' : usd(c.etat === 'fermee' && c.ecart != null ? c.enCaisse + c.ecart : c.enCaisse))+'</span></li>';
      }).join('')+'</ul>' : '<p class="vide">Aucune caisse ouverte ces 30 derniers jours.</p>';

      // ---- 4. qui a fait quoi ----
      fil = S.filDuJour({
        devises:devises, users:users, dossiers:r[1].data||[], commandes:r[2].data||[], locations:r[3].data||[],
        momo_transactions:r[4].data||[], paiements:r[5].data||[], mouvements_caisse:mouvements
      }, today);
      var agents = []; fil.forEach(function(e){ if(e.agent && agents.indexOf(e.agent) < 0) agents.push(e.agent); });
      if(agentFiltre && agents.indexOf(agentFiltre) < 0) agentFiltre = '';
      $('#chips').innerHTML = agents.length > 1 ? [''].concat(agents.sort()).map(function(a){
        var n = a ? fil.filter(function(e){ return e.agent === a; }).length : fil.length;
        return '<button class="chip'+(a === agentFiltre ? ' on' : '')+'" data-a="'+esc(a)+'">'+(a ? esc(a) : 'Tout le monde')+' <span>'+n+'</span></button>';
      }).join('') : '';
      renderFil();

      $('#maj').textContent = 'Mis à jour à '+heure(new Date().toISOString());
      if(err) h.toast('Attention : '+err.error.message);
    }

    $('#chips').addEventListener('click', function(e){
      var b = e.target.closest('button[data-a]'); if(!b) return;
      agentFiltre = b.dataset.a;
      root.querySelectorAll('#chips .chip').forEach(function(x){ x.classList.toggle('on', x === b); });
      renderFil();
    });
    $('#refreshBtn').addEventListener('click', load);
    // rafraîchissement automatique tant que CETTE page est affichée (le conteneur est réutilisé par les autres modules)
    var jeton = {}; root._aujJeton = jeton;
    timer = setInterval(function(){
      if(root._aujJeton !== jeton || !$('#hero')) return clearInterval(timer);
      if(!document.hidden) load();
    }, 120000);
    await load();
  }
});
