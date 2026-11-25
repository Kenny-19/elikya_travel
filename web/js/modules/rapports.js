/* modules/rapports.js — Rapport mensuel de la direction (Pilotage).
   Synthèse du mois : totaux par module, activité par jour, tableau journalier, par agent,
   meilleurs clients. Export CSV (Excel, « ; ») et impression / PDF (navigateur).
   Calculs dans js/stats.js (testés). Montants en USD. */
Elikya.registerModule({
  id: 'rapports',
  label: 'Rapports',
  group: 'Pilotage',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var SERIES = [
      { key:'Voyage', label:'Voyage', color:'var(--series-1)' },
      { key:'Location', label:'Location', color:'var(--series-2)' },
      { key:'Fourniture', label:'Fourniture', color:'var(--series-3)' },
      { key:'Mobile Money', label:'Mobile Money (volume)', color:'var(--series-4)' }
    ];
    var now = new Date();
    var mois = now.getFullYear()+'-'+String(now.getMonth()+1).padStart(2,'0');
    var lignes = []; // tableau journalier courant (pour l'export)

    function usd(n){ return h.money(Math.round((n||0)*100)/100, 'USD'); }
    function cell(n){ return n ? usd(n) : '<span style="color:var(--faint)">—</span>'; }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function libMois(ym){ try{ return new Date(ym+'-01T00:00:00').toLocaleDateString('fr-FR',{month:'long',year:'numeric'}); }catch(e){ return ym; } }
    function jourCourt(k){ try{ return new Date(k+'T00:00:00').toLocaleDateString('fr-FR',{weekday:'short',day:'2-digit',month:'short'}); }catch(e){ return k; } }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Pilotage · Direction</div><h1 class="pf">Rapports</h1>'+
        '<p id="sousTitre">Synthèse mensuelle par module. Montants en USD.</p></div>'+
        '<div class="toolbar no-print" style="margin:0">'+
          '<input type="month" id="mois" value="'+mois+'" max="'+mois+'" aria-label="Mois du rapport">'+
          '<button class="btn" id="csvBtn">⤓ Exporter (Excel)</button>'+
          '<button class="btn primary" id="printBtn" style="width:auto">Imprimer / PDF</button>'+
        '</div></div>'+
      '<div class="row tiles-auto" id="tiles" style="margin-bottom:16px"></div>'+
      '<div class="card" style="margin-bottom:16px"><h3>Activité par jour</h3><div id="chart"><span class="spin"></span></div></div>'+
      '<div class="card tight" style="margin-bottom:16px"><div style="padding:17px 17px 0"><h3>Synthèse journalière</h3></div>'+
        '<div class="table-wrap"><table><thead><tr><th>Jour</th><th class="num">Voyage</th><th class="num">Location</th><th class="num">Fourniture</th>'+
        '<th class="num">Mobile Money</th><th class="num">Commissions</th><th class="num">Caisse entrées</th><th class="num">Caisse sorties</th>'+
        '<th class="num">Ventes du jour</th></tr></thead><tbody id="jours">'+h.loadingRow(9)+'</tbody></table></div></div>'+
      '<div class="grid2">'+
        '<div class="card tight"><div style="padding:17px 17px 0"><h3>Par agent</h3></div><div class="table-wrap"><table><thead><tr>'+
          '<th>Agent</th><th class="num">Dossiers</th><th class="num">Voyage</th><th class="num">Transactions</th><th class="num">Mobile Money</th><th class="num">Mvts caisse</th>'+
          '</tr></thead><tbody id="agents"></tbody></table></div></div>'+
        '<div class="card tight"><div style="padding:17px 17px 0"><h3>Meilleurs clients</h3></div><div class="table-wrap"><table><thead><tr>'+
          '<th>Client</th><th class="num">Ventes</th><th class="num">Montant</th></tr></thead><tbody id="clients"></tbody></table></div></div>'+
      '</div>';

    async function load(){
      mois = $('#mois').value || mois;
      var M = S.monthRange(mois);
      $('#sousTitre').textContent = 'Synthèse de '+libMois(mois)+(M.days.length ? ' (du 1er au '+(+M.days[M.days.length-1].slice(8))+')' : '')+'. Montants en USD.';
      if(!M.days.length){ $('#jours').innerHTML = '<tr><td colspan="9" style="padding:22px;text-align:center;color:var(--muted)">Mois à venir.</td></tr>'; return; }
      var end = new Date(M.to); end.setHours(23,59,59,999);
      var q = { gte:{ cree_le: M.from.toISOString() }, lte:{ cree_le: end.toISOString() } };

      $('#jours').innerHTML = h.loadingRow(9);
      var r = await Promise.all([
        store.select('devises', {}),
        store.select('dossiers', q),
        store.select('commandes', q),
        store.select('momo_transactions', q),
        store.select('mouvements_caisse', q),
        store.select('users', {}),
        store.select('clients', {}),
        store.select('locations', q)
      ]);
      if(!$('#jours')) return;   // on a changé d'écran pendant le chargement
      var err = r.filter(function(x){ return x.error; })[0];
      if(err) h.toast('Attention : '+err.error.message);

      var devises = r[0].data||[];
      var entries = S.journal({ devises:devises, dossiers:r[1].data||[], commandes:r[2].data||[], momo_transactions:r[3].data||[], locations:r[7].data||[] });
      var tot = S.totals(entries, M.from, M.to);
      var cz = S.caisse({ devises:devises, mouvements_caisse:r[4].data||[] });
      var cin = 0, cout = 0;
      Object.keys(cz.parJour).forEach(function(k){ cin += cz.parJour[k].entrees; cout += cz.parJour[k].sorties; });

      $('#tiles').innerHTML =
        tileHtml('Voyage', usd(tot['Voyage']), tot.nb['Voyage']+' dossier(s)')+
        tileHtml('Location', usd(tot['Location']), tot.nb['Location']+' location(s)')+
        tileHtml('Fourniture', usd(tot['Fourniture']), tot.nb['Fourniture']+' commande(s)')+
        tileHtml('Mobile Money', usd(tot['Mobile Money']), 'Commissions : '+usd(tot.frais))+
        tileHtml('Caisse', usd(cin - cout), 'Entrées '+usd(cin)+' · sorties '+usd(cout));

      var daily = S.daily(entries, M.days);
      Elikya.charts.stackedColumns($('#chart'), { rows:daily, series:SERIES, format:usd, label:'Activité par jour du mois, en dollars' });

      var fraisJour = {};
      entries.forEach(function(e){ if(e.frais) fraisJour[e.jour] = (fraisJour[e.jour]||0) + e.frais; });
      lignes = daily.map(function(d){
        var c = cz.parJour[d.jour] || { entrees:0, sorties:0 };
        return { jour:d.jour, voyage:d['Voyage'], location:d['Location'], fourniture:d['Fourniture'], momo:d['Mobile Money'],
                 frais: Math.round((fraisJour[d.jour]||0)*100)/100, entrees: Math.round(c.entrees*100)/100,
                 sorties: Math.round(c.sorties*100)/100, ventes: Math.round((d['Voyage']+d['Location']+d['Fourniture'])*100)/100 };
      });
      var T = lignes.reduce(function(a, l){ Object.keys(l).forEach(function(k){ if(k !== 'jour') a[k] = (a[k]||0) + l[k]; }); return a; }, {});
      $('#jours').innerHTML = lignes.map(function(l){
        return '<tr><td class="cap">'+esc(jourCourt(l.jour))+'</td><td class="num tnum">'+cell(l.voyage)+'</td><td class="num tnum">'+cell(l.location)+'</td><td class="num tnum">'+cell(l.fourniture)+
          '</td><td class="num tnum">'+cell(l.momo)+'</td><td class="num tnum">'+cell(l.frais)+'</td><td class="num tnum">'+cell(l.entrees)+
          '</td><td class="num tnum">'+cell(l.sorties)+'</td><td class="num tnum"><b>'+cell(l.ventes)+'</b></td></tr>';
      }).join('')+
        '<tr style="background:var(--panel2);font-weight:700"><td>Total du mois</td><td class="num tnum">'+usd(T.voyage)+'</td><td class="num tnum">'+usd(T.location)+'</td><td class="num tnum">'+usd(T.fourniture)+
        '</td><td class="num tnum">'+usd(T.momo)+'</td><td class="num tnum">'+usd(T.frais)+'</td><td class="num tnum">'+usd(T.entrees)+
        '</td><td class="num tnum">'+usd(T.sorties)+'</td><td class="num tnum">'+usd(T.ventes)+'</td></tr>';

      var ag = S.parAgent(entries, r[4].data||[], r[5].data||[]);
      $('#agents').innerHTML = ag.length ? ag.map(function(a){
        return '<tr><td>'+esc(a.nom)+'</td><td class="num tnum">'+a.nbVoyage+'</td><td class="num tnum">'+cell(a['Voyage'])+
          '</td><td class="num tnum">'+a.nbMomo+'</td><td class="num tnum">'+cell(a['Mobile Money'])+'</td><td class="num tnum">'+a.mouvements+'</td></tr>';
      }).join('') : '<tr><td colspan="6" style="padding:20px;text-align:center;color:var(--muted)">Aucune saisie ce mois-ci.</td></tr>';

      var top = S.topClients(entries, r[6].data||[], 10);
      $('#clients').innerHTML = top.length ? top.map(function(c){
        return '<tr><td>'+esc(c.nom)+'</td><td class="num tnum">'+c.nb+'</td><td class="num tnum"><b>'+usd(c.ca)+'</b></td></tr>';
      }).join('') : '<tr><td colspan="3" style="padding:20px;text-align:center;color:var(--muted)">Aucune vente ce mois-ci.</td></tr>';
    }

    function tileHtml(label, value, sub){
      return '<div class="card kpi"><div class="lab">'+label+'</div><div class="val tnum">'+value+'</div><div class="sub">'+sub+'</div></div>';
    }

    function exportCsv(){
      if(!lignes.length){ h.toast('Rien à exporter pour ce mois'); return; }
      var csv = S.toCsv(lignes, [
        { key:'jour', label:'Jour' }, { key:'voyage', label:'Voyage (USD)' }, { key:'location', label:'Location (USD)' }, { key:'fourniture', label:'Fourniture (USD)' },
        { key:'momo', label:'Mobile Money volume (USD)' }, { key:'frais', label:'Commissions MoMo (USD)' },
        { key:'entrees', label:'Caisse entrées (USD)' }, { key:'sorties', label:'Caisse sorties (USD)' }, { key:'ventes', label:'Ventes du jour (USD)' }
      ]);
      // BOM UTF-8 : Excel affiche correctement les accents
      var blob = new Blob(['﻿'+csv], { type:'text/csv;charset=utf-8' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'elikya-rapport-'+mois+'.csv';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(function(){ URL.revokeObjectURL(a.href); }, 1000);
      h.toast('Export '+a.download+' ✓');
    }

    $('#mois').addEventListener('change', load);
    $('#csvBtn').addEventListener('click', exportCsv);
    $('#printBtn').addEventListener('click', function(){
      root.querySelectorAll('details.viz-table').forEach(function(d){ d.open = true; });
      window.print();
    });
    await load();
  }
});
