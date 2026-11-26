/* modules/momo.js — Suivi Mobile Money : solde de chaque opérateur + journal des transactions.
   Le solde bouge tout seul à chaque opération réussie (déclencheur db/momo_soldes.sql) ; « Corriger » le remet d'après le téléphone. */
Elikya.registerModule({
  id: 'momo',
  label: 'Mobile Money',
  group: 'Activités',
  async render(root){
    var store = Elikya.data, h = Elikya.h;   // en ligne prioritaire, secours local
    var OPS = {airtel:'Airtel Money', orange:'Orange Money', mpesa:'M-Pesa'};
    var TYPES = {depot:'Dépôt', retrait:'Retrait', transfert:'Transfert'};
    var STATUTS = {reussi:['Réussi','ok'], en_attente:['En attente','warn'], echec:['Échec','crit']};
    var PERIODES = {jour:"Aujourd'hui", semaine:'7 jours', mois:'30 jours', tout:'Tout'};

    root.innerHTML =
      '<div class="banner">Module Mobile Money · solde de chaque opérateur et journal des transactions (dépôt, retrait, transfert).</div>'+
      '<div class="phead"><div><div class="eyebrow">Module · Suivi</div><h1 class="pf">Mobile Money</h1>'+
        '<p>Montants en USD. Le solde de chaque opérateur bouge tout seul : un dépôt ou un transfert le fait baisser, un retrait le fait monter.</p></div>'+
        '<button class="btn primary" id="newBtn" data-ecriture style="width:auto">＋ Nouvelle transaction</button></div>'+

      '<div class="row k3" id="comptes" style="margin-bottom:16px"></div>'+

      '<div class="card hidden" id="formCard" data-ecriture style="margin-bottom:16px">'+
        '<h3 style="margin:0 0 12px">Nouvelle transaction</h3>'+
        '<form id="tForm"><div class="formgrid">'+
          field('Opérateur','<select id="fCompte" required></select>')+
          field('Type','<select id="fType">'+opts(TYPES)+'</select>')+
          field('Montant (USD)','<input id="fMontant" inputmode="decimal" placeholder="0" required>')+
          field('Frais / commission (USD)','<input id="fFrais" inputmode="decimal" placeholder="0">')+
          field('Téléphone client','<input id="fTel" inputmode="tel" placeholder="+243…">')+
          field('Statut','<select id="fStatut">'+Object.keys(STATUTS).map(function(k){return '<option value="'+k+'">'+STATUTS[k][0]+'</option>';}).join('')+'</select>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="saveBtn" style="width:auto">Enregistrer</button><button class="btn" type="button" id="cancelBtn">Annuler</button></div></form>'+
      '</div>'+

      '<div class="card hidden" id="soldeCard" data-ecriture style="margin-bottom:16px">'+
        '<h3 style="margin:0 0 12px" id="soldeTitle">Corriger le solde</h3>'+
        '<form id="sForm"><div class="formgrid">'+
          field('Solde affiché sur le téléphone (USD)','<input id="sSolde" inputmode="decimal" required>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="sSave" style="width:auto">Mettre à jour</button><button class="btn" type="button" id="sCancel">Annuler</button></div></form>'+
      '</div>'+

      '<div class="row k4" style="margin-bottom:16px">'+
        kpi('kNb','Transactions')+kpi('kVol','Volume réussi')+kpi('kFrais','Frais / commissions')+kpi('kKo','Échecs / en attente')+
      '</div>'+

      '<div class="toolbar">'+
        '<div class="field" style="margin:0"><select id="pSel">'+opts(PERIODES)+'</select></div>'+
        '<div class="field" style="margin:0"><select id="oSel"><option value="">Tous opérateurs</option></select></div>'+
        '<div class="field" style="margin:0"><select id="tSel"><option value="">Tous types</option>'+opts(TYPES)+'</select></div>'+
        '<span class="eyebrow" id="listCount" style="margin-left:6px">—</span>'+
        '<button class="btn" id="refreshBtn" style="margin-left:auto">↻ Rafraîchir</button>'+
      '</div>'+
      '<div class="card tight"><div class="table-wrap"><table>'+
        '<thead><tr><th>Date</th><th>Opérateur</th><th>Type</th><th>Client</th><th class="num">Montant</th><th class="num">Frais</th><th>Statut</th></tr></thead>'+
        '<tbody id="rows">'+h.loadingRow(7)+'</tbody></table></div></div>';

    function kpi(id,lab){ return '<div class="card kpi"><div class="lab">'+lab+'</div><div class="val tnum" id="'+id+'">—</div></div>'; }
    function field(lab,inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }
    function opts(map){ return Object.keys(map).map(function(k){return '<option value="'+k+'">'+map[k]+'</option>';}).join(''); }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(sel){ return root.querySelector(sel); }
    function parseNum(v){ return parseFloat(String(v||'').replace(/\s/g,'').replace(',','.')); }
    function usd(n){ return h.money(Math.round(Number(n||0)*100)/100, 'USD'); }
    function fmtDate(t){ try{ return new Date(t).toLocaleString('fr-FR',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'}); }catch(e){ return '—'; } }
    function since(p){
      if(p==='tout') return null;
      var d = new Date(); d.setHours(0,0,0,0);
      if(p==='semaine') d.setDate(d.getDate()-6);
      if(p==='mois') d.setDate(d.getDate()-29);
      return d.toISOString();
    }

    // ----- état -----
    var comptes=[], agentId=null, editCompte=null;

    async function loadAgent(){
      if(!Elikya.user) return;
      var u = await store.select('users', { eq:{ auth_id:Elikya.user.id }, single:true });
      agentId = (u.data && u.data.id) || null;
    }

    async function loadComptes(){
      var res = await store.select('momo_comptes', { order:['id'] });
      var box = $('#comptes');
      if(res.error){ box.innerHTML = '<div class="card" style="color:var(--crit)">Erreur : '+esc(res.error.message)+'</div>'; return; }
      comptes = res.data||[];
      var total = comptes.reduce(function(s,c){return s+Number(c.solde||0);},0);
      box.innerHTML = comptes.map(function(c){
        return '<div class="card kpi"><div class="lab" style="display:flex;justify-content:space-between;align-items:center">'+
          '<span>'+esc(OPS[c.operateur]||c.operateur)+'</span>'+
          '<button class="btn" data-ecriture data-solde="'+c.id+'" style="padding:4px 10px;font-size:12px">Corriger</button></div>'+
          '<div class="val tnum">'+usd(c.solde)+'</div>'+
          '<div style="font-size:12px;color:var(--muted);margin-top:4px">'+(total?Math.round(Number(c.solde||0)/total*100):0)+' % du float total ('+usd(total)+')</div></div>';
      }).join('') || '<div class="card" style="color:var(--muted)">Aucun compte opérateur.</div>';
      var opt = comptes.map(function(c){return '<option value="'+c.id+'">'+esc(OPS[c.operateur]||c.operateur)+'</option>';}).join('');
      $('#fCompte').innerHTML = opt;
      var keep = $('#oSel').value;
      $('#oSel').innerHTML = '<option value="">Tous opérateurs</option>'+opt;
      $('#oSel').value = keep;
    }

    async function loadTransactions(){
      var rows = $('#rows');
      rows.innerHTML = h.loadingRow(7);
      var o = { embed:['momo_comptes(operateur)'], order:['cree_le', false], limit:500, eq:{}, gte:{} };
      var from = since($('#pSel').value); if(from) o.gte.cree_le = from;
      if($('#oSel').value) o.eq.compte_id = parseInt($('#oSel').value,10);
      if($('#tSel').value) o.eq.type = $('#tSel').value;
      var res = await store.select('momo_transactions', o);
      if(res.error){ rows.innerHTML = '<tr><td colspan="7" style="padding:22px;text-align:center;color:var(--crit)">Erreur : '+esc(res.error.message)+'</td></tr>'; return; }
      var data = res.data||[];
      if(!data.length){
        rows.innerHTML = '<tr><td colspan="7" style="padding:26px;text-align:center;color:var(--muted)">Aucune transaction sur cette période.</td></tr>';
      } else {
        rows.innerHTML = data.map(function(t){
          var st = STATUTS[t.statut] || [t.statut,'neutral'];
          var op = t.momo_comptes && t.momo_comptes.operateur;
          var statut = !Elikya.readOnly && t.statut==='en_attente'
            ? '<select data-statut="'+t.id+'" style="font:inherit;font-size:12px;padding:3px 6px;border:1px solid var(--line);border-radius:7px;background:var(--panel2);color:var(--ink)">'+
                Object.keys(STATUTS).map(function(k){return '<option value="'+k+'"'+(k===t.statut?' selected':'')+'>'+STATUTS[k][0]+'</option>';}).join('')+'</select>'
            : h.pill(st[0], st[1]);
          return '<tr><td class="tnum">'+fmtDate(t.cree_le)+'</td>'+
            '<td>'+esc(OPS[op]||op||'—')+'</td>'+
            '<td>'+esc(TYPES[t.type]||t.type)+'</td>'+
            '<td class="tnum">'+esc(t.client_tel||'—')+'</td>'+
            '<td class="num tnum">'+usd(t.montant)+'</td>'+
            '<td class="num tnum">'+usd(t.frais)+'</td>'+
            '<td>'+statut+'</td></tr>';
        }).join('');
      }
      var vol=0, frais=0, ko=0;
      data.forEach(function(t){
        if(t.statut==='reussi'){ vol+=Number(t.montant||0); frais+=Number(t.frais||0); }
        else ko++;
      });
      $('#kNb').textContent = data.length;
      $('#kVol').textContent = usd(vol);
      $('#kFrais').textContent = usd(frais);
      $('#kKo').textContent = ko;
      $('#listCount').textContent = data.length+' transaction'+(data.length>1?'s':'');
    }

    // ----- interactions -----
    var formCard = $('#formCard'), soldeCard = $('#soldeCard');
    $('#newBtn').addEventListener('click', function(){ soldeCard.classList.add('hidden'); formCard.classList.toggle('hidden'); });
    $('#cancelBtn').addEventListener('click', function(){ formCard.classList.add('hidden'); });
    $('#sCancel').addEventListener('click', function(){ soldeCard.classList.add('hidden'); });
    $('#refreshBtn').addEventListener('click', function(){ loadComptes(); loadTransactions(); });
    ['#pSel','#oSel','#tSel'].forEach(function(s){ $(s).addEventListener('change', loadTransactions); });

    $('#comptes').addEventListener('click', function(e){
      var b = e.target.closest('[data-solde]'); if(!b) return;
      editCompte = comptes.filter(function(c){return String(c.id)===b.dataset.solde;})[0];
      if(!editCompte) return;
      $('#soldeTitle').textContent = 'Corriger le solde · '+(OPS[editCompte.operateur]||editCompte.operateur);
      $('#sSolde').value = String(editCompte.solde);
      formCard.classList.add('hidden'); soldeCard.classList.remove('hidden');
      $('#sSolde').focus();
    });

    $('#sForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var v = parseNum($('#sSolde').value);
      if(isNaN(v) || v<0){ h.toast('Solde invalide'); return; }
      var btn=$('#sSave'); btn.disabled=true; btn.textContent='Mise à jour…';
      var res = await store.update('momo_comptes', editCompte.id, { solde: v });
      btn.disabled=false; btn.textContent='Mettre à jour';
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast('Solde '+(OPS[editCompte.operateur]||'')+' mis à jour'+h.saved(res));
      soldeCard.classList.add('hidden');
      loadComptes();
    });

    $('#rows').addEventListener('change', async function(e){
      var s = e.target.closest('[data-statut]'); if(!s) return;
      s.disabled = true;
      var res = await store.update('momo_transactions', s.dataset.statut, { statut: s.value });
      if(res.error){ h.toast('Erreur : '+res.error.message); s.disabled=false; return; }
      h.toast('Statut mis à jour'+h.saved(res));
      loadTransactions();
    });

    $('#tForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var montant = parseNum($('#fMontant').value);
      var frais = $('#fFrais').value ? parseNum($('#fFrais').value) : 0;
      if(isNaN(montant) || montant<=0){ h.toast('Montant invalide'); return; }
      if(isNaN(frais) || frais<0){ h.toast('Frais invalides'); return; }
      var btn=$('#saveBtn'); btn.disabled=true; btn.textContent='Enregistrement…';
      var payload = {
        compte_id: parseInt($('#fCompte').value,10),
        type: $('#fType').value,
        montant: montant,
        frais: frais,
        client_tel: $('#fTel').value.trim() || null,
        statut: $('#fStatut').value,
        agent_id: agentId
      };
      var res = await store.insert('momo_transactions', payload);
      btn.disabled=false; btn.textContent='Enregistrer';
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast((TYPES[payload.type]||'Transaction')+' enregistré'+h.saved(res));
      $('#tForm').reset(); formCard.classList.add('hidden');
      loadTransactions();
    });

    $('#pSel').value = 'tout';
    await loadAgent();
    await loadComptes();
    await loadTransactions();
  }
});
