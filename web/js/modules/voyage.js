/* modules/voyage.js — Voyage (site direction) : billets, visas, hôtels, assurances, packages.
   Même lecture que l'app agents (agents/lib/ui/pages/voyage_page.dart) : une ligne par dossier
   avec « payé / reste à payer », l'avancement et l'étape du visa ; alerte des départs proches
   pas encore soldés. Consultation pour la direction ; création et encaissement marqués
   data-ecriture → super admin seulement. Règles : Elikya.stats.voy* (testées, identiques à l'app). */
Elikya.registerModule({
  id: 'voyage',
  label: 'Voyage',
  group: 'Activités',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var TYPES = { billet:'Billet d’avion', visa:'Visa', hotel:'Hôtel', assurance:'Assurance', package:'Package' };
    var ICONES = { billet:'✈', visa:'🛂', hotel:'🏨', assurance:'🛡', package:'🧳' };
    var AVANC = { devis:['Devis','info'], confirme:['Confirmé','navy'], termine:['Voyage effectué','ok'], annule:['Annulé','neutral'] };
    var PAIE = { non_paye:'crit', acompte:'warn', solde:'ok', trop_percu:'ok', sans_montant:'neutral' };
    var ETAPES = { a_deposer:'À déposer', depose:'Déposé', en_traitement:'En traitement', obtenu:'Obtenu', refuse:'Refusé' };
    var MODES = { especes:'Espèces', mobile_money:'Mobile money', banque:'Banque' };
    var dossiers = [], paiements = [], clients = [], devises = [], filtre = 'actifs', encaisserId = null;

    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function code(id){ var d = devises.filter(function(x){ return String(x.id) === String(id); })[0]; return d ? d.code : 'USD'; }
    function argent(n, deviseId){ return h.money(Math.round((Number(n)||0)*100)/100, code(deviseId)); }
    function dLong(k){ if(!k) return ''; try{ return new Date(k+'T00:00:00').toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short'}); }catch(e){ return k; } }
    function joursAvant(k){ if(!k) return null; return Math.round((Date.UTC(+k.slice(0,4), +k.slice(5,7)-1, +k.slice(8,10)) - Date.UTC(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())) / 864e5); }
    function field(lab, inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }
    function paiementDe(d){ return S.voyPaiement(d, S.voyPaiementsDe(paiements, d.id), devises); }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Module · Suivi</div><h1 class="pf">Voyage</h1>'+
        '<p>Billets, visas, hôtels, assurances : avancement et paiements de chaque dossier.</p></div>'+
        '<div class="toolbar" style="margin:0"><button class="btn" id="refreshBtn">↻ Rafraîchir</button>'+
        '<button class="btn primary" id="newBtn" data-ecriture style="width:auto">＋ Nouveau dossier</button></div></div>'+
      '<div class="loc-chips" id="chips"></div><div id="alerte"></div>'+
      // nouveau dossier (super admin)
      '<div class="card hidden" id="formCard" data-ecriture style="margin:0 0 16px"><h3>Nouveau dossier</h3><form id="dForm"><div class="formgrid">'+
        field('Service','<select id="fType">'+Object.keys(TYPES).map(function(k){ return '<option value="'+k+'">'+TYPES[k]+'</option>'; }).join('')+'</select>')+
        field('Client','<select id="fClient" required></select>')+
        field('Destination / trajet / ville','<input id="fDest">')+
        field('Pays (visa) ou hôtel','<input id="fPaysHotel">')+
        field('Départ / arrivée','<input type="date" id="fDep">')+field('Retour / départ hôtel','<input type="date" id="fRet">')+
        field('Compagnie (facultatif)','<input id="fComp">')+field('Référence / PNR (facultatif)','<input id="fRef">')+
        field('Prix total','<input id="fMontant" inputmode="decimal" required>')+field('Devise','<select id="fDevise"></select>')+
        field('Statut','<select id="fStatut"><option value="confirme">Confirmé par le client</option><option value="devis">Simple devis</option></select>')+
      '</div><div class="toolbar" style="margin:14px 0 0"><button class="btn primary" type="submit" style="width:auto">Enregistrer</button>'+
      '<button class="btn" type="button" data-close="formCard">Annuler</button></div></form></div>'+
      // encaisser (super admin)
      '<div class="card hidden" id="encCard" data-ecriture style="margin:0 0 16px"><h3 id="encTitre">Encaisser</h3><p id="encInfo" style="margin:0 0 10px;color:var(--muted)"></p>'+
        '<form id="encForm"><div class="formgrid">'+
          field('Montant reçu','<input id="eMontant" inputmode="decimal" required>')+field('Devise','<select id="eDevise"></select>')+
          field('Mode','<select id="eMode">'+Object.keys(MODES).map(function(k){ return '<option value="'+k+'">'+MODES[k]+'</option>'; }).join('')+'</select>')+
          field('N° de transaction (facultatif)','<input id="eRef">')+
        '</div><div class="toolbar" style="margin:14px 0 0"><button class="btn primary" type="submit" style="width:auto">Enregistrer le paiement</button>'+
        '<button class="btn" type="button" data-close="encCard">Annuler</button></div></form></div>'+
      '<div class="toolbar"><div class="seg" id="seg">'+
        [['actifs','En cours'],['non_soldes','Pas soldés'],['visas','Visas'],['archives','Effectués / annulés'],['tous','Tous']]
          .map(function(f){ return '<button data-f="'+f[0]+'">'+f[1]+'</button>'; }).join('')+'</div>'+
        '<div class="field" style="margin:0;min-width:260px"><input id="q" placeholder="Rechercher (client, réf., destination…)"></div></div>'+
      '<div id="liste"><span class="spin"></span></div>';

    async function load(){
      var r = await Promise.all([
        store.select('dossiers', { embed:['clients(nom,telephone)','devises(code)'], order:['cree_le', false], limit:800 }),
        store.select('paiements', { eq:{ source_type:'dossier' }, limit:3000 }),
        store.select('clients', { order:['nom'] }),
        store.select('devises', { order:['id'] })
      ]);
      if(!$('#liste')) return;
      var err = r.filter(function(x){ return x.error; })[0];
      if(err) h.toast('Erreur : '+err.error.message);
      dossiers = r[0].data||[]; paiements = r[1].data||[]; clients = r[2].data||[]; devises = r[3].data||[];
      $('#fClient').innerHTML = clients.map(function(c){ return '<option value="'+c.id+'">'+esc(c.nom)+'</option>'; }).join('');
      $('#fDevise').innerHTML = $('#eDevise').innerHTML = devises.map(function(d){ return '<option value="'+d.id+'">'+esc(d.code)+'</option>'; }).join('');
      draw();
    }

    function details(d){
      var p = [];
      if(d.type === 'visa'){ p.push(ETAPES[d.etape_visa || 'a_deposer']); if(d.date_depart) p.push('voyage prévu '+dLong(d.date_depart)); }
      else if(d.type === 'hotel'){ if(d.hotel) p.push(d.hotel); if(d.date_depart) p.push('du '+dLong(d.date_depart)+(d.date_retour ? ' au '+dLong(d.date_retour) : '')); }
      else { if(d.date_depart) p.push('départ '+dLong(d.date_depart)+(d.date_retour ? ' · retour '+dLong(d.date_retour) : (d.type === 'billet' ? ' · aller simple' : ''))); if(d.compagnie) p.push(d.compagnie); }
      if(d.reference) p.push('réf. '+d.reference);
      if(d.passager) p.push('voyageur : '+d.passager);
      return p.join(' · ');
    }

    function draw(){
      root.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('on', b.dataset.f === filtre); });
      var et = {}; dossiers.forEach(function(d){ et[d.id] = paiementDe(d); });
      var actifs = dossiers.filter(function(d){ var a = S.voyAvancement(d); return a === 'devis' || a === 'confirme'; });
      var urgents = actifs.filter(function(d){ var n = joursAvant(d.date_depart); return et[d.id].reste > 0 && n !== null && n >= 0 && n <= 3; });
      var departs = actifs.filter(function(d){ var n = joursAvant(d.date_depart); return n !== null && n >= 0 && n <= 7; }).length;
      var visas = actifs.filter(function(d){ return d.type === 'visa' && d.etape_visa !== 'obtenu' && d.etape_visa !== 'refuse'; }).length;
      var taux = S.tauxMap(devises), reste = actifs.reduce(function(s, d){ return s + et[d.id].reste / (taux[String(d.devise_id)] || 1); }, 0);
      var chips = [['navy','📁', actifs.length, 'dossier(s) en cours'], ['info','✈', departs, 'départ(s) dans 7 jours'],
                   ['warn','💵', h.money(Math.round(reste*100)/100, 'USD'), 'reste à encaisser'], ['navy','🛂', visas, 'visa(s) en cours']];
      $('#chips').innerHTML = chips.filter(function(c, i){ return i === 0 || (i === 2 ? reste > 0 : c[2] > 0); }).map(function(c){
        return '<div class="card loc-chip"><span class="ic '+c[0]+'">'+c[1]+'</span><b class="tnum">'+c[2]+'</b><span>'+c[3]+'</span></div>'; }).join('');
      $('#alerte').innerHTML = urgents.length ? '<div class="loc-alerte"><b>⚠ '+(urgents.length === 1 ? '1 client part bientôt et n’a pas tout payé.' : urgents.length+' clients partent bientôt et n’ont pas tout payé.')+'</b>'+
        urgents.map(function(d){ return '<div>'+esc((d.clients && d.clients.nom) || '')+' '+esc((d.clients && d.clients.telephone) || '')+' · départ '+esc(dLong(d.date_depart))+' · reste '+esc(argent(et[d.id].reste, d.devise_id))+'</div>'; }).join('')+'</div>' : '';

      var q = $('#q').value.trim().toLowerCase();
      var liste = dossiers.filter(function(d){
        var a = S.voyAvancement(d), p = et[d.id];
        var ok = filtre === 'actifs' ? (a === 'devis' || a === 'confirme') : filtre === 'non_soldes' ? (a !== 'annule' && p.reste > 0)
          : filtre === 'visas' ? (d.type === 'visa' && a !== 'annule') : filtre === 'archives' ? (a === 'termine' || a === 'annule') : true;
        if(!ok) return false;
        if(!q) return true;
        return [d.ref, d.clients && d.clients.nom, d.destination, d.pays, d.hotel, d.passager, d.reference].some(function(x){ return String(x||'').toLowerCase().indexOf(q) >= 0; });
      });
      if(filtre === 'actifs') liste.sort(function(a, b){ return (a.date_depart || '9999') < (b.date_depart || '9999') ? -1 : 1; });

      $('#liste').innerHTML = liste.length ? liste.map(function(d){
        var a = S.voyAvancement(d), p = et[d.id], total = Number(d.montant)||0, av = AVANC[a];
        var ou = d.type === 'visa' ? (d.pays || d.destination) : (d.destination || d.hotel);
        var pct = total > 0 ? Math.min(100, Math.round(p.paye / total * 100)) : 0;
        return '<div class="card voy-ligne"><span class="voy-ic">'+(ICONES[d.type] || '🧳')+'</span>'+
          '<div class="voy-txt"><div><b>'+esc((d.clients && d.clients.nom) || '—')+'</b>'+(ou ? ' <span class="voy-ou">→ '+esc(ou)+'</span>' : '')+'</div>'+
            '<span class="voy-det">'+esc(TYPES[d.type] || d.type)+' · '+esc(d.ref || '')+(details(d) ? ' · '+esc(details(d)) : '')+'</span>'+
            '<span>'+h.pill(av[0], av[1] === 'navy' ? 'info' : av[1])+(p.code !== 'sans_montant' ? ' '+h.pill(p.libelle, PAIE[p.code]) : '')+'</span></div>'+
          '<div class="voy-paie"><b class="tnum">'+(total > 0 ? argent(total, d.devise_id) : '—')+'</b>'+
            (total > 0 ? '<div class="meter voy-'+PAIE[p.code]+'"><b style="width:'+pct+'%"></b></div><span>'+
              (p.reste > 0 ? 'Payé '+argent(p.paye, d.devise_id)+' · reste '+argent(p.reste, d.devise_id) : 'Tout est payé')+'</span>' : '')+'</div>'+
          '<div class="voy-act">'+(a !== 'annule' && p.reste > 0 ? '<button class="btn primary" data-ecriture data-enc="'+d.id+'" style="width:auto">Encaisser</button>' : '')+'</div></div>';
      }).join('') : '<div class="card" style="color:var(--muted);padding:24px;text-align:center">Aucun dossier dans cette liste.</div>';
    }

    // ----- super admin : nouveau dossier -----
    $('#dForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var t = $('#fType').value, ph = $('#fPaysHotel').value.trim() || null;
      var dep = $('#fDep').value || null, ret = $('#fRet').value || null;
      if(dep && ret && ret < dep){ h.toast('La date de retour est avant le départ'); return; }
      var res = await store.insert('dossiers', {
        ref:'ELK-'+String(Date.now()).slice(8), client_id:$('#fClient').value, type:t,
        destination:$('#fDest').value.trim() || null, pays: t === 'visa' ? ph : null, hotel: t === 'hotel' ? ph : null,
        date_depart:dep, date_retour: t === 'visa' ? null : ret, compagnie:$('#fComp').value.trim() || null,
        reference:$('#fRef').value.trim() || null, etape_visa: t === 'visa' ? 'a_deposer' : null,
        montant:parseFloat(String($('#fMontant').value).replace(',', '.')) || 0, devise_id:parseInt($('#fDevise').value, 10),
        statut:$('#fStatut').value, agent_id:(Elikya.profile && Elikya.profile.user_id) || null
      });
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast('Dossier '+res.data.ref+' enregistré'+h.saved(res)); $('#dForm').reset(); $('#formCard').classList.add('hidden'); load();
    });

    // ----- super admin : encaisser -----
    function ouvrirEncaisser(id){
      var d = dossiers.filter(function(x){ return String(x.id) === String(id); })[0], p = paiementDe(d);
      encaisserId = d.id;
      $('#encTitre').textContent = 'Encaisser · '+((d.clients && d.clients.nom) || '');
      $('#encInfo').textContent = 'Total '+argent(d.montant, d.devise_id)+' · déjà payé '+argent(p.paye, d.devise_id)+' · reste '+argent(p.reste, d.devise_id);
      $('#eMontant').value = p.reste; $('#eDevise').value = d.devise_id; $('#eMode').value = 'especes'; $('#eRef').value = '';
      $('#formCard').classList.add('hidden'); $('#encCard').classList.remove('hidden'); $('#encCard').scrollIntoView({ behavior:'smooth', block:'center' });
    }
    $('#encForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var m = parseFloat(String($('#eMontant').value).replace(',', '.'));
      if(!(m > 0)){ h.toast('Montant invalide'); return; }
      var res = await store.insert('paiements', { source_type:'dossier', source_id:encaisserId, mode:$('#eMode').value, montant:m,
        devise_id:parseInt($('#eDevise').value, 10), reference:$('#eRef').value.trim() || null, recu_par:(Elikya.profile && Elikya.profile.user_id) || null });
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast('Paiement enregistré'+h.saved(res)); $('#encCard').classList.add('hidden'); load();
    });

    // ----- interactions -----
    $('#refreshBtn').addEventListener('click', load);
    $('#newBtn').addEventListener('click', function(){ $('#encCard').classList.add('hidden'); $('#formCard').classList.remove('hidden'); });
    $('#seg').addEventListener('click', function(e){ var b = e.target.closest('button[data-f]'); if(b){ filtre = b.dataset.f; draw(); } });
    $('#q').addEventListener('input', draw);
    root.addEventListener('click', function(e){
      var c = e.target.closest('[data-close]'); if(c){ $('#'+c.dataset.close).classList.add('hidden'); return; }
      var en = e.target.closest('[data-enc]'); if(en) ouvrirEncaisser(en.dataset.enc);
    });

    await load();
  }
});
