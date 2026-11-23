/* modules/voyage.js — Module de référence (complet) : suivi des dossiers de voyage */
Elikya.registerModule({
  id: 'voyage',
  label: 'Voyage',
  group: 'Activités',
  async render(root){
    var store = Elikya.data, h = Elikya.h;   // toujours passer par Elikya.data (en ligne + secours local)
    var TYPES = {billet:"Billet",visa:"Visa",hotel:"Hôtel",assurance:"Assurance",package:"Package"};
    var STATUTS = {devis:["Devis","info"],confirme:["Confirmé","ok"],paye:["Payé","ok"],en_cours:["En cours","warn"],annule:["Annulé","crit"]};

    root.innerHTML =
      '<div class="banner">Module Voyage · suivi des dossiers (billets, visa, hôtel, assurance, package).</div>'+
      '<div class="phead"><div><div class="eyebrow">Module · Suivi</div><h1 class="pf">Voyage</h1>'+
        '<p>Dossiers clients lus et enregistrés en temps réel dans la base.</p></div>'+
        '<button class="btn gold" id="newBtn" data-ecriture style="width:auto">＋ Nouveau dossier</button></div>'+
      '<div class="row k4" style="margin-bottom:16px">'+
        kpi('kTotal','Dossiers')+kpi('kOk','Confirmés / payés')+kpi('kPend','En cours / devis')+kpi('kSum','Montant total')+
      '</div>'+
      '<div class="card hidden" id="formCard" data-ecriture style="margin-bottom:16px">'+
        '<h3 style="margin:0 0 12px">Nouveau dossier</h3>'+
        '<form id="dForm"><div class="formgrid">'+
          field('Client','<select id="fClient" required></select>')+
          field('Type','<select id="fType" required>'+Object.keys(TYPES).map(function(k){return '<option value="'+k+'">'+TYPES[k]+'</option>';}).join('')+'</select>')+
          field('Destination','<input id="fDest" placeholder="Ville / pays">')+
          field('Montant','<input id="fMontant" inputmode="decimal" placeholder="0" required>')+
          field('Devise','<select id="fDevise" required></select>')+
          field('Statut','<select id="fStatut"><option value="devis">Devis</option><option value="confirme">Confirmé</option><option value="paye">Payé</option><option value="en_cours">En cours</option><option value="annule">Annulé</option></select>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn gold" type="submit" id="saveBtn" style="width:auto">Enregistrer</button><button class="btn" type="button" id="cancelBtn">Annuler</button></div></form>'+
      '</div>'+
      '<div class="toolbar"><span class="eyebrow" id="listCount">—</span><button class="btn" id="refreshBtn" style="margin-left:auto">↻ Rafraîchir</button></div>'+
      '<div class="card tight"><div class="table-wrap"><table>'+
        '<thead><tr><th>Réf.</th><th>Client</th><th>Type</th><th>Destination</th><th class="num">Montant</th><th>Statut</th></tr></thead>'+
        '<tbody id="rows">'+h.loadingRow(6)+'</tbody></table></div></div>';

    function kpi(id,lab){ return '<div class="card kpi"><div class="lab">'+lab+'</div><div class="val tnum" id="'+id+'">—</div></div>'; }
    function field(lab,inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }

    // Référentiels (clients + devises)
    var clients=[], devises=[];
    async function loadRefs(){
      var c = await store.select('clients', { order:['nom'] });
      var d = await store.select('devises', { order:['id'] });
      clients = c.data||[]; devises = d.data||[];
      root.querySelector('#fClient').innerHTML = clients.map(function(x){return '<option value="'+x.id+'">'+x.nom+'</option>';}).join('');
      root.querySelector('#fDevise').innerHTML = devises.map(function(x){return '<option value="'+x.id+'">'+x.code+'</option>';}).join('');
    }

    async function loadDossiers(){
      var rows = root.querySelector('#rows');
      rows.innerHTML = h.loadingRow(6);
      var res = await store.select('dossiers', { embed:['clients(nom)','devises(code)'], order:['cree_le', false] });
      if(res.error){ rows.innerHTML = '<tr><td colspan="6" style="padding:22px;text-align:center;color:var(--crit)">Erreur : '+res.error.message+'</td></tr>'; return; }
      var data = res.data||[];
      if(!data.length){
        rows.innerHTML = '<tr><td colspan="6" style="padding:26px;text-align:center;color:var(--muted)">Aucun dossier.'+h.invite('Clique « Nouveau dossier ».')+'</td></tr>';
      } else {
        rows.innerHTML = data.map(function(d){
          var st = STATUTS[d.statut] || [d.statut,'neutral'];
          return '<tr><td><span class="mono-ref">'+(d.ref||'')+'</span></td>'+
            '<td>'+((d.clients&&d.clients.nom)||'—')+'</td>'+
            '<td>'+(TYPES[d.type]||d.type)+'</td>'+
            '<td>'+(d.destination||'—')+'</td>'+
            '<td class="num tnum">'+h.money(d.montant, d.devises&&d.devises.code)+'</td>'+
            '<td>'+h.pill(st[0], st[1])+'</td></tr>';
        }).join('');
      }
      var ok=0,pend=0,sum=0;
      data.forEach(function(d){ if(d.statut==='confirme'||d.statut==='paye')ok++; else if(d.statut!=='annule')pend++; sum+=Number(d.montant||0); });
      root.querySelector('#kTotal').textContent = data.length;
      root.querySelector('#kOk').textContent = ok;
      root.querySelector('#kPend').textContent = pend;
      root.querySelector('#kSum').textContent = h.num(sum)+' $';
      root.querySelector('#listCount').textContent = data.length+' dossier'+(data.length>1?'s':'');
    }

    // interactions
    var formCard = root.querySelector('#formCard');
    root.querySelector('#newBtn').addEventListener('click', function(){ formCard.classList.toggle('hidden'); });
    root.querySelector('#cancelBtn').addEventListener('click', function(){ formCard.classList.add('hidden'); });
    root.querySelector('#refreshBtn').addEventListener('click', loadDossiers);
    root.querySelector('#dForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var btn = root.querySelector('#saveBtn'); btn.disabled=true; btn.textContent="Enregistrement…";
      var payload = {
        ref: 'ELK-'+Date.now().toString().slice(-5),
        client_id: root.querySelector('#fClient').value,
        type: root.querySelector('#fType').value,
        destination: root.querySelector('#fDest').value||null,
        montant: parseFloat(root.querySelector('#fMontant').value)||0,
        devise_id: parseInt(root.querySelector('#fDevise').value,10),
        statut: root.querySelector('#fStatut').value
      };
      var res = await store.insert('dossiers', payload);
      btn.disabled=false; btn.textContent="Enregistrer";
      if(res.error){ h.toast("Erreur : "+res.error.message); return; }
      h.toast("Dossier "+payload.ref+" enregistré"+h.saved(res));
      root.querySelector('#dForm').reset();
      formCard.classList.add('hidden');
      loadDossiers();
    });

    await Promise.all([loadRefs(), loadDossiers()]);
  }
});
