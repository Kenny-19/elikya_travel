/* modules/dashboard.js — Tableau de bord de la direction (Pilotage).
   Vue consolidée sur une période : ventes voyage / fourniture, volume mobile money, caisse,
   activité par jour, alertes à traiter, float mobile money, meilleurs clients.
   Calculs dans js/stats.js (testés), graphique dans js/charts.js. Montants en USD. */
Elikya.registerModule({
  id: 'dashboard',
  label: 'Tableau de bord',
  group: 'Pilotage',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var PERIODES = { jour:"Aujourd'hui", semaine:'7 jours', mois:'30 jours', mtd:'Ce mois' };
    var PREC = { jour:'hier', semaine:'7 jours précédents', mois:'30 jours précédents', mtd:'même durée le mois d’avant' };
    var OPS = { airtel:'Airtel Money', orange:'Orange Money', mpesa:'M-Pesa' };
    var SERIES = [
      { key:'Voyage', label:'Voyage', color:'var(--series-1)' },
      { key:'Location', label:'Location', color:'var(--series-2)' },
      { key:'Fourniture', label:'Fourniture', color:'var(--series-3)' },
      { key:'Mobile Money', label:'Mobile Money (volume)', color:'var(--series-4)' }
    ];
    var preset = 'semaine';
    try{ preset = localStorage.getItem('elikya-dash-periode') || preset; }catch(e){}
    if(!PERIODES[preset]) preset = 'semaine';

    function usd(n){ return h.money(Math.round((n||0)*100)/100, 'USD'); }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Pilotage · Direction</div><h1 class="pf">Tableau de bord</h1>'+
        '<p>Vue d’ensemble de l’activité d’Elikya Group. Montants en USD (CDF converti au taux du jour).</p></div>'+
        '<div class="toolbar" style="margin:0"><div class="seg" id="seg">'+
          Object.keys(PERIODES).map(function(k){ return '<button data-p="'+k+'">'+PERIODES[k]+'</button>'; }).join('')+
        '</div><button class="btn" id="refreshBtn">↻</button></div></div>'+
      '<div class="row tiles-auto" id="tiles" style="margin-bottom:16px"></div>'+
      '<div class="grid2" style="margin-bottom:16px">'+
        '<div class="card"><h3 id="chartTitle">Activité par jour</h3><div id="chart"><span class="spin"></span></div></div>'+
        '<div class="card"><h3>À traiter</h3><ul class="alerts" id="alerts"><li><span class="spin"></span></li></ul></div>'+
      '</div>'+
      '<div class="grid2">'+
        '<div class="card"><h3>Meilleurs clients de la période</h3><div id="top"></div></div>'+
        '<div class="card"><h3>Float Mobile Money</h3><div id="float"></div></div>'+
      '</div>';

    function tile(label, value, deltaPct, sub){
      var d = '';
      if(deltaPct === null) d = '<div class="delta">nouveau vs '+PREC[preset]+'</div>';
      else if(deltaPct !== undefined){
        var cls = deltaPct > 0 ? 'up' : deltaPct < 0 ? 'down' : '';
        d = '<div class="delta '+cls+'">'+(deltaPct > 0 ? '▲ +' : deltaPct < 0 ? '▼ ' : '= ')+deltaPct+' % vs '+PREC[preset]+'</div>';
      }
      return '<div class="card kpi"><div class="lab">'+label+'</div><div class="val tnum">'+value+'</div>'+d+
        (sub ? '<div class="sub">'+sub+'</div>' : '')+'</div>';
    }

    async function load(){
      root.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('on', b.dataset.p === preset); });
      var P = S.periodRange(preset);
      // le graphique montre au moins 7 jours, même pour « Aujourd'hui »
      var chartDays = P.length >= 7 ? P.days : S.periodRange('semaine').days;
      var chartFrom = new Date(chartDays[0]+'T00:00:00');
      var fetchFrom = (chartFrom < P.prevFrom ? chartFrom : P.prevFrom).toISOString();
      var since = { gte:{ cree_le: fetchFrom } };

      var r = await Promise.all([
        store.select('devises', {}),
        store.select('dossiers', since),
        store.select('commandes', since),
        store.select('momo_transactions', since),
        store.select('caisse_sessions', { embed:['users(nom)'], order:['jour', false], limit:90 }),
        store.select('produits', {}),
        store.select('momo_comptes', { order:['id'] }),
        store.select('clients', {}),
        // états en cours, quelle que soit la date
        store.select('momo_transactions', { eq:{ statut:'en_attente' } }),
        store.select('commandes', { eq:{ statut:'a_livrer' } }),
        store.select('dossiers', { eq:{ statut:'devis' } }),
        // départs dans les 3 jours (pour l'alerte « pas soldé »)
        store.select('dossiers', { embed:['clients(nom)'], gte:{ date_depart:S.dayKey(new Date()) }, lte:{ date_depart:S.dayKey(new Date(Date.now() + 3*864e5)) } }),
        store.select('locations', since),                                   // r[12]
        store.select('locations', { eq:{ statut:'en_cours' } }),            // r[13] : retours en retard
        store.select('paiements', { eq:{ source_type:'dossier' }, limit:3000 })  // r[14]
      ]);
      var err = r.filter(function(x){ return x.error; })[0];
      var devises = r[0].data||[], sessions = r[4].data||[];

      // mouvements des sessions utiles (ouvertes, ou clôturées depuis 30 jours)
      var il30j = S.dayKey(new Date(Date.now() - 30*864e5));
      var utiles = sessions.filter(function(s){ return s.statut === 'ouverte' || s.jour >= il30j; });
      var oldest = utiles.reduce(function(a, s){ return s.jour < a ? s.jour : a; }, S.dayKey(new Date()));
      var mv = await store.select('mouvements_caisse', { gte:{ cree_le: new Date(oldest+'T00:00:00').toISOString() } });
      if(!$('#tiles')) return;   // on a changé d'écran pendant le chargement
      var mouvements = mv.data||[];

      var src = { devises:devises, dossiers:r[1].data||[], commandes:r[2].data||[], momo_transactions:r[3].data||[], locations:r[12].data||[] };
      var entries = S.journal(src);
      var cur = S.totals(entries, P.from, P.to), prev = S.totals(entries, P.prevFrom, P.prevTo);
      var cz = S.caisse({ devises:devises, caisse_sessions:utiles, mouvements_caisse:mouvements });

      $('#tiles').innerHTML =
        tile('Ventes voyage', usd(cur['Voyage']), S.delta(cur['Voyage'], prev['Voyage']), cur.nb['Voyage']+' dossier(s)')+
        tile('Location de véhicules', usd(cur['Location']), S.delta(cur['Location'], prev['Location']), cur.nb['Location']+' location(s)')+
        tile('Ventes fourniture', usd(cur['Fourniture']), S.delta(cur['Fourniture'], prev['Fourniture']), cur.nb['Fourniture']+' commande(s)')+
        tile('Volume Mobile Money', usd(cur['Mobile Money']), S.delta(cur['Mobile Money'], prev['Mobile Money']), 'Commissions : '+usd(cur.frais))+
        tile('Caisse (sessions ouvertes)', usd(cz.soldeOuvert), undefined, cz.ouvertes.length+' session(s) ouverte(s) · solde théorique');

      $('#chartTitle').textContent = 'Activité par jour'+(P.length >= 7 ? '' : ' · 7 derniers jours');
      Elikya.charts.stackedColumns($('#chart'), {
        rows: S.daily(entries, chartDays), series: SERIES, format: usd,
        label: 'Activité par jour et par module, en dollars'
      });

      var periodTx = (r[3].data||[]).filter(function(t){ var k = S.dayKey(t.cree_le); return k >= P.days[0] && k <= P.days[P.days.length-1]; });
      var al = S.alertes({
        devises:devises, produits:r[5].data||[], caisse_sessions:utiles, mouvements_caisse:mouvements,
        momo_transactions: (r[8].data||[]).concat(periodTx.filter(function(t){ return t.statut === 'echec'; })),
        commandes: r[9].data||[], dossiers: r[10].data||[], departs: r[11].data||[], paiements: r[14].data||[], locations: r[13].data||[]
      });
      var ICON = { crit:['Urgent','crit'], warn:['À voir','warn'], info:['Info','info'] };
      $('#alerts').innerHTML = al.length ? al.map(function(a){
        return '<li>'+h.pill(ICON[a.niveau][0], ICON[a.niveau][1])+'<div>'+esc(a.texte)+'<span class="mod">'+esc(a.module)+'</span></div></li>';
      }).join('') : '<li style="color:var(--muted)">Rien à signaler ✓</li>';

      var top = S.topClients(entries.filter(function(e){ return e.jour >= P.days[0]; }), r[7].data||[], 5);
      $('#top').innerHTML = top.length ? '<div class="table-wrap"><table><thead><tr><th>Client</th><th class="num">Ventes</th><th class="num">Montant</th></tr></thead><tbody>'+
        top.map(function(c){ return '<tr><td>'+esc(c.nom)+'</td><td class="num tnum">'+c.nb+'</td><td class="num tnum"><b>'+usd(c.ca)+'</b></td></tr>'; }).join('')+
        '</tbody></table></div>' : '<p style="color:var(--muted);margin:0">Aucune vente sur la période.</p>';

      var comptes = r[6].data||[], floatTot = comptes.reduce(function(a, c){ return a + Number(c.solde||0); }, 0);
      $('#float').innerHTML = comptes.length ? comptes.map(function(c){
        var pct = floatTot ? Math.round(Number(c.solde||0) / floatTot * 100) : 0;
        return '<div style="margin-bottom:12px"><div style="display:flex;font-size:13px"><span>'+esc(OPS[c.operateur]||c.operateur)+'</span>'+
          '<b class="tnum" style="margin-left:auto">'+usd(c.solde)+'</b><span class="tnum" style="color:var(--muted);width:46px;text-align:right">'+pct+' %</span></div>'+
          '<div class="meter"><b style="width:'+pct+'%"></b></div></div>';
      }).join('')+'<div style="display:flex;font-size:13px;border-top:1px solid var(--line);padding-top:9px"><span>Total relevé</span><b class="tnum" style="margin-left:auto">'+usd(floatTot)+'</b></div>'
        : '<p style="color:var(--muted);margin:0">Aucun compte opérateur.</p>';

      if(err) h.toast('Attention : '+err.error.message);
    }

    $('#seg').addEventListener('click', function(e){
      var b = e.target.closest('button[data-p]'); if(!b) return;
      preset = b.dataset.p;
      try{ localStorage.setItem('elikya-dash-periode', preset); }catch(err){}
      load();
    });
    $('#refreshBtn').addEventListener('click', load);
    await load();
  }
});
