/* modules/location.js — Location de véhicules (site direction).
   Même présentation que l'app agents (agents/lib/ui/pages/location_page.dart) : une carte par
   véhicule avec son état en couleur, puis les locations en cours / à venir.
   Consultation pour la direction ; les actions (louer, remettre les clés, véhicule rendu,
   ajouter un véhicule) sont marquées data-ecriture → visibles pour le super admin seulement.
   Règles (jours, conflits, état) : Elikya.stats.loc* (testées, identiques à l'app). */
Elikya.registerModule({
  id: 'location',
  label: 'Location',
  group: 'Activités',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var vehicules = [], locations = [], clients = [], devises = [], histo = false;
    var STYLE = { disponible:['ok','✓'], reserve_plus_tard:['ok','✓'], loue:['info','🔑'], a_remettre:['navy','📅'],
                  retard:['crit','⚠'], entretien:['warn','🔧'], hors_service:['neutral','⛔'] };
    var ORDRE = ['a_remettre','retard','disponible','reserve_plus_tard','loue','entretien','hors_service'];

    function usd(n){ return h.money(Math.round((Number(n)||0)*100)/100, 'USD'); }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function today(){ return S.dayKey(new Date()); }
    function dLong(k){ try{ return new Date(k+'T00:00:00').toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short'}); }catch(e){ return k; } }
    function veh(id){ return vehicules.filter(function(v){ return String(v.id) === String(id); })[0]; }
    function field(lab, inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Module · Suivi</div><h1 class="pf">Location de véhicules</h1>'+
        '<p>État du parc et des locations, avec ou sans chauffeur. Montants en USD.</p></div>'+
        '<div class="toolbar" style="margin:0"><button class="btn" id="refreshBtn">↻ Rafraîchir</button>'+
        '<button class="btn" id="addVeh" data-ecriture>＋ Ajouter un véhicule</button>'+
        '<button class="btn primary" id="newLoc" data-ecriture style="width:auto">＋ Nouvelle location</button></div></div>'+
      '<div class="loc-chips" id="chips"></div>'+
      '<div id="alerte"></div>'+
      // formulaire véhicule (super admin)
      '<div class="card hidden" id="vCard" data-ecriture style="margin:16px 0"><h3>Ajouter un véhicule</h3><form id="vForm"><div class="formgrid">'+
        field('Plaque d’immatriculation','<input id="vImmat" required>')+field('Marque','<input id="vMarque" required placeholder="Toyota…">')+
        field('Modèle','<input id="vModele" placeholder="Hilux, Prado…">')+field('Places','<input id="vPlaces" inputmode="numeric" value="5" required>')+
        field('Carburant','<select id="vCarb"><option>Diesel</option><option>Essence</option></select>')+
        field('Prix par jour (USD)','<input id="vTarif" inputmode="decimal" required>')+
        field('Supplément chauffeur / jour (USD)','<input id="vChauf" inputmode="decimal" value="0">')+
      '</div><div class="toolbar" style="margin:14px 0 0"><button class="btn primary" type="submit" style="width:auto">Enregistrer</button>'+
      '<button class="btn" type="button" data-close="vCard">Annuler</button></div></form></div>'+
      // formulaire location (super admin)
      '<div class="card hidden" id="lCard" data-ecriture style="margin:16px 0"><h3>Nouvelle location</h3><form id="lForm"><div class="formgrid">'+
        field('Véhicule','<select id="lVeh" required></select>')+field('Client','<select id="lCli" required></select>')+
        field('Du','<input type="date" id="lDeb" required>')+field('Au (jour de retour inclus)','<input type="date" id="lFin" required>')+
        field('Chauffeur','<label style="display:flex;gap:8px;align-items:center;font-weight:600;text-transform:none;letter-spacing:0;color:var(--ink)"><input type="checkbox" id="lChauf" style="width:auto"> Avec chauffeur</label>')+
        field('Nom du chauffeur (facultatif)','<input id="lChaufNom">')+
        field('Total (USD)','<input id="lMontant" inputmode="decimal" required>')+
      '</div><p id="lInfo" style="margin:6px 0 0;color:var(--muted);font-size:13px"></p>'+
      '<div class="toolbar" style="margin:14px 0 0"><button class="btn primary" type="submit" id="lSave" style="width:auto">Enregistrer</button>'+
      '<button class="btn" type="button" data-close="lCard">Annuler</button></div></form></div>'+
      '<h2 class="loc-h">Nos véhicules</h2><div class="veh-grid" id="cartes"><span class="spin"></span></div>'+
      '<h2 class="loc-h">Locations en cours et à venir</h2><div id="aVenir"></div>'+
      '<button class="lnk" id="histoBtn" style="margin-top:12px"></button><div id="histo"></div>';

    async function load(){
      var r = await Promise.all([
        store.select('vehicules', { order:['marque'] }),
        store.select('locations', { embed:['clients(nom,telephone)'], order:['date_debut', false], limit:600 }),
        store.select('clients', { order:['nom'] }),
        store.select('devises', {})
      ]);
      if(!$('#cartes')) return;
      var err = r.filter(function(x){ return x.error; })[0];
      if(err) h.toast('Erreur : '+err.error.message);
      vehicules = (r[0].data||[]).filter(function(v){ return v.actif !== false; });
      locations = r[1].data||[]; clients = r[2].data||[]; devises = r[3].data||[];
      draw();
    }

    function ligne(l){
      var v = veh(l.vehicule_id), t = today(), j = S.locJours(l.date_debut, l.date_fin);
      var st = l.statut === 'reservee' ? ['Réservée','info'] : l.statut === 'en_cours' ? (S.locEnRetard(l, t) ? ['En retard','crit'] : ['En cours','info'])
             : l.statut === 'terminee' ? ['Terminée','ok'] : ['Annulée','neutral'];
      var act = l.statut === 'reservee' ? '<button class="btn primary" data-ecriture data-act="en_cours" data-id="'+l.id+'" style="width:auto;padding:7px 12px">Remettre les clés</button> '+
                  '<button class="lnk" data-ecriture data-act="annulee" data-id="'+l.id+'">Annuler</button>'
              : l.statut === 'en_cours' ? '<button class="btn primary" data-ecriture data-act="terminee" data-id="'+l.id+'" style="width:auto;padding:7px 12px">Véhicule rendu</button>' : '';
      return '<div class="card loc-ligne">'+h.pill(st[0], st[1])+'<div class="loc-txt"><b>'+esc((l.clients && l.clients.nom) || '—')+' · '+esc(v ? v.marque+' '+v.immatriculation : '')+'</b>'+
        '<span>Du '+esc(dLong(l.date_debut))+' au '+esc(dLong(l.date_fin))+' · '+j+' jour'+(j > 1 ? 's' : '')+
        (l.avec_chauffeur ? ' · avec chauffeur'+(l.chauffeur ? ' ('+esc(l.chauffeur)+')' : '') : '')+'</span></div>'+
        '<b class="tnum">'+usd(l.montant)+'</b><div class="loc-act">'+act+'</div></div>';
    }

    function draw(){
      var t = today(), etats = {};
      vehicules.forEach(function(v){ etats[v.id] = S.locEtat(v, locations, t); });
      var nb = function(c){ return vehicules.filter(function(v){ return etats[v.id].code === c; }).length; };
      var retards = locations.filter(function(l){ return S.locEnRetard(l, t); });
      var chips = [['ok','✓', nb('disponible') + nb('reserve_plus_tard'), 'disponible(s)'], ['info','🔑', nb('loue') + nb('retard'), 'en location'],
                   ['navy','📅', nb('a_remettre'), 'clés à remettre'], ['crit','⚠', retards.length, 'en retard'], ['warn','🔧', nb('entretien'), 'en entretien']];
      $('#chips').innerHTML = chips.filter(function(c, i){ return i === 0 || c[2] > 0; }).map(function(c){
        return '<div class="card loc-chip"><span class="ic '+c[0]+'">'+c[1]+'</span><b class="tnum">'+c[2]+'</b><span>'+c[3]+'</span></div>';
      }).join('');
      $('#alerte').innerHTML = retards.length ? '<div class="loc-alerte"><b>⚠ '+(retards.length === 1 ? '1 véhicule aurait dû être rendu.' : retards.length+' véhicules auraient dû être rendus.')+'</b>'+
        retards.map(function(l){ var v = veh(l.vehicule_id);
          return '<div>'+esc(v ? v.marque+' '+v.immatriculation : '')+' · '+esc((l.clients && l.clients.nom) || '')+' '+esc((l.clients && l.clients.telephone) || '')+' · prévu le '+esc(dLong(l.date_fin))+'</div>'; }).join('')+'</div>' : '';

      var tries = vehicules.slice().sort(function(a, b){ return ORDRE.indexOf(etats[a.id].code) - ORDRE.indexOf(etats[b.id].code); });
      $('#cartes').innerHTML = tries.length ? tries.map(function(v){
        var e = etats[v.id], s = STYLE[e.code] || STYLE.hors_service, l = e.location;
        var bouton = (e.code === 'disponible' || e.code === 'reserve_plus_tard') ? '<button class="btn primary" data-ecriture data-louer="'+v.id+'">Louer</button>'
          : e.code === 'a_remettre' ? '<button class="btn primary" data-ecriture data-act="en_cours" data-id="'+l.id+'">Remettre les clés</button>'
          : (e.code === 'loue' || e.code === 'retard') ? '<button class="btn primary" data-ecriture data-act="terminee" data-id="'+l.id+'">Véhicule rendu</button>' : '';
        return '<div class="card veh"><div class="veh-etat '+s[0]+'">'+s[1]+' '+esc(e.libelle)+'</div><div class="veh-corps">'+
          '<b class="veh-nom">'+esc(v.marque+' '+(v.modele||''))+'</b><span class="veh-sub">'+esc(v.immatriculation)+' · '+esc(v.places)+' places'+(v.carburant ? ' · '+esc(v.carburant) : '')+'</span>'+
          '<b>'+usd(v.tarif_jour)+' / jour</b>'+(Number(v.tarif_chauffeur_jour) > 0 ? '<span class="veh-sub">Avec chauffeur : + '+usd(v.tarif_chauffeur_jour)+' / jour</span>' : '')+
          (l && l.clients ? '<span class="veh-loc">'+esc(l.clients.nom)+' · '+esc(dLong(l.date_debut))+' → '+esc(dLong(l.date_fin))+'</span>' : '')+
          bouton+'</div></div>';
      }).join('') : '<div class="card" style="color:var(--muted);padding:24px;text-align:center">Aucun véhicule enregistré.</div>';

      var aVenir = locations.filter(function(l){ return l.statut === 'reservee' || l.statut === 'en_cours'; })
        .sort(function(a, b){ return a.date_debut < b.date_debut ? -1 : 1; });
      $('#aVenir').innerHTML = aVenir.length ? aVenir.map(ligne).join('') : '<div class="card" style="color:var(--muted);padding:20px;text-align:center">Aucune location en cours ni à venir.</div>';
      var passees = locations.filter(function(l){ return l.statut === 'terminee' || l.statut === 'annulee'; }).slice(0, 30);
      $('#histoBtn').textContent = passees.length ? (histo ? '▲ Masquer l’historique' : '▼ Voir l’historique ('+passees.length+' dernières)') : '';
      $('#histo').innerHTML = histo ? passees.map(ligne).join('') : '';
    }

    // ----- formulaire location (super admin) -----
    function ouvrirLocation(vehId){
      var libres = vehicules.filter(function(v){ return v.statut === 'disponible'; });
      if(!libres.length){ h.toast('Aucun véhicule disponible'); return; }
      $('#lVeh').innerHTML = libres.map(function(v){ return '<option value="'+v.id+'">'+esc(v.marque+' '+(v.modele||'')+' · '+v.immatriculation+' · '+usd(v.tarif_jour)+'/jour')+'</option>'; }).join('');
      $('#lCli').innerHTML = '<option value="">— Choisir le client —</option>'+clients.map(function(c){ return '<option value="'+c.id+'">'+esc(c.nom)+'</option>'; }).join('');
      if(vehId) $('#lVeh').value = vehId;
      $('#lDeb').value = today(); $('#lFin').value = today(); $('#lChauf').checked = false; $('#lChaufNom').value = ''; $('#lMontant').dataset.manuel = '';
      recalc(); $('#vCard').classList.add('hidden'); $('#lCard').classList.remove('hidden'); $('#lCli').focus();
    }
    function recalc(){
      var v = veh($('#lVeh').value), d = $('#lDeb').value, f = $('#lFin').value, info = $('#lInfo'), save = $('#lSave');
      if(!v || !d || !f){ info.textContent = ''; return; }
      if(f < d){ info.innerHTML = '<span style="color:var(--crit)">La date de retour est avant la date de départ.</span>'; save.disabled = true; return; }
      var j = S.locJours(d, f), c = S.locConflit(locations, v.id, d, f);
      if(!$('#lMontant').dataset.manuel) $('#lMontant').value = S.locMontant(v, d, f, $('#lChauf').checked);
      info.innerHTML = c ? '<span style="color:var(--crit);font-weight:600">Ce véhicule est déjà pris du '+esc(dLong(c.date_debut))+' au '+esc(dLong(c.date_fin))+' — choisissez d’autres dates.</span>'
        : j+' jour'+(j > 1 ? 's' : '')+' × '+usd(Number(v.tarif_jour) + ($('#lChauf').checked ? Number(v.tarif_chauffeur_jour) : 0))+' (modifiable si remise).';
      save.disabled = !!c;
    }
    ['#lVeh','#lDeb','#lFin','#lChauf'].forEach(function(s){ $(s).addEventListener('change', recalc); });
    $('#lMontant').addEventListener('input', function(){ this.dataset.manuel = '1'; });
    $('#lForm').addEventListener('submit', async function(e){
      e.preventDefault();
      if(!$('#lCli').value){ h.toast('Choisissez le client'); return; }
      var usdId = (devises.filter(function(d){ return d.code === 'USD'; })[0] || devises[0] || {}).id;
      var d = $('#lDeb').value, departAujourdhui = d === today();
      var res = await store.insert('locations', {
        ref:'LOC-'+String(Date.now()).slice(7), client_id:$('#lCli').value, vehicule_id:$('#lVeh').value, date_debut:d, date_fin:$('#lFin').value,
        avec_chauffeur:$('#lChauf').checked, chauffeur:$('#lChauf').checked && $('#lChaufNom').value.trim() ? $('#lChaufNom').value.trim() : null,
        montant:parseFloat(String($('#lMontant').value).replace(',', '.')) || 0, devise_id:usdId, statut: departAujourdhui ? 'en_cours' : 'reservee',
        agent_id:(Elikya.profile && Elikya.profile.user_id) || null
      });
      if(res.error){ h.toast(/chevauchement/.test(res.error.message) ? 'Ce véhicule vient d’être réservé sur ces dates.' : 'Erreur : '+res.error.message); return; }
      h.toast('Location '+res.data.ref+' enregistrée'+h.saved(res)); $('#lCard').classList.add('hidden'); load();
    });

    // ----- formulaire véhicule (super admin) -----
    $('#vForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var immat = $('#vImmat').value.trim().toUpperCase();
      if(vehicules.some(function(v){ return String(v.immatriculation).toUpperCase() === immat; })){ h.toast('Ce véhicule existe déjà'); return; }
      var res = await store.insert('vehicules', { immatriculation:immat, marque:$('#vMarque').value.trim(), modele:$('#vModele').value.trim() || null,
        places:parseInt($('#vPlaces').value, 10) || 5, carburant:$('#vCarb').value, tarif_jour:parseFloat($('#vTarif').value.replace(',', '.')) || 0,
        tarif_chauffeur_jour:parseFloat($('#vChauf').value.replace(',', '.')) || 0, statut:'disponible' });
      if(res.error){ h.toast(res.error.code === '23505' ? 'Ce véhicule existe déjà' : 'Erreur : '+res.error.message); return; }
      h.toast('Véhicule ajouté'+h.saved(res)); $('#vForm').reset(); $('#vCard').classList.add('hidden'); load();
    });

    // ----- interactions -----
    $('#refreshBtn').addEventListener('click', load);
    $('#addVeh').addEventListener('click', function(){ $('#lCard').classList.add('hidden'); $('#vCard').classList.remove('hidden'); $('#vImmat').focus(); });
    $('#newLoc').addEventListener('click', function(){ ouvrirLocation(null); });
    $('#histoBtn').addEventListener('click', function(){ histo = !histo; draw(); });
    root.addEventListener('click', async function(e){
      var c = e.target.closest('[data-close]'); if(c){ $('#'+c.dataset.close).classList.add('hidden'); return; }
      var lo = e.target.closest('[data-louer]'); if(lo){ ouvrirLocation(lo.dataset.louer); return; }
      var a = e.target.closest('[data-act]'); if(!a) return;
      if(a.dataset.act === 'annulee' && !confirm('Annuler cette location ? Le véhicule redevient libre sur ces dates.')) return;
      var msg = { en_cours:'Clés remises — location en cours', terminee:'Véhicule rendu — location terminée', annulee:'Location annulée' }[a.dataset.act];
      a.disabled = true;
      var res = await store.update('locations', a.dataset.id, { statut:a.dataset.act });
      h.toast(res.error ? 'Erreur : '+res.error.message : msg+h.saved(res)); load();
    });

    await load();
  }
});
