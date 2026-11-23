/* modules/caisse.js — Suivi caisse : sessions journalières, mouvements (entrées/sorties), solde.
   Suivi uniquement : on JOURNALISE les mouvements, aucun traitement d'argent. */
Elikya.registerModule({
  id: 'caisse',
  label: 'Caisse & Finances',
  group: 'Activités',
  async render(root){
    var store = Elikya.data, h = Elikya.h;   // en ligne prioritaire, secours local
    var MODULES = ['Voyage','Fourniture','Mobile money','Logistique','Admin','Autre'];
    var SOURCES = {paiement:'Paiement', depense:'Dépense', momo:'Mobile money', autre:'Autre'};

    root.innerHTML =
      '<div class="banner">Module Caisse · journal des entrées / sorties par session, avec solde théorique et clôture.</div>'+
      '<div class="phead"><div><div class="eyebrow">Module · Suivi</div><h1 class="pf">Caisse &amp; Finances</h1>'+
        '<p>Une session par jour et par agent. Les totaux sont exprimés en USD (CDF converti au taux de la table devises).</p></div>'+
        '<div class="toolbar" style="margin:0">'+
          '<button class="btn" id="openBtn" data-ecriture>＋ Ouvrir une session</button>'+
          '<button class="btn primary" id="newBtn" data-ecriture style="width:auto">＋ Mouvement</button>'+
        '</div></div>'+

      // sélection de session
      '<div class="toolbar">'+
        '<div class="field" style="margin:0;min-width:280px"><select id="sessSel"></select></div>'+
        '<span id="sessPill"></span>'+
        '<button class="btn" id="closeBtn" data-ecriture style="margin-left:auto">Clôturer la session</button>'+
        '<button class="btn" id="refreshBtn">↻ Rafraîchir</button>'+
      '</div>'+

      '<div class="row k4" style="margin-bottom:16px">'+
        kpi('kOuv','Solde d’ouverture')+kpi('kIn','Entrées')+kpi('kOut','Sorties')+kpi('kSolde','Solde théorique')+
      '</div>'+
      '<div class="card hidden" id="ecartCard" style="margin-bottom:16px"></div>'+

      // formulaire : ouverture de session
      '<div class="card hidden" id="openCard" data-ecriture style="margin-bottom:16px">'+
        '<h3 style="margin:0 0 12px">Ouvrir une session de caisse</h3>'+
        '<form id="oForm"><div class="formgrid">'+
          field('Jour','<input type="date" id="oJour" required>')+
          field('Solde d’ouverture (USD)','<input id="oSolde" inputmode="decimal" placeholder="0" required>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="oSave" style="width:auto">Ouvrir</button><button class="btn" type="button" data-cancel="openCard">Annuler</button></div></form>'+
      '</div>'+

      // formulaire : mouvement
      '<div class="card hidden" id="formCard" data-ecriture style="margin-bottom:16px">'+
        '<h3 style="margin:0 0 12px">Nouveau mouvement</h3>'+
        '<form id="mForm"><div class="formgrid">'+
          field('Sens','<select id="fSens"><option value="entree">Entrée</option><option value="sortie">Sortie</option></select>')+
          field('Libellé','<input id="fLib" placeholder="Ex. Billet ELK-2041, carburant…" required>')+
          field('Module','<select id="fMod">'+MODULES.map(function(m){return '<option>'+m+'</option>';}).join('')+'</select>')+
          field('Nature','<select id="fSrc">'+Object.keys(SOURCES).map(function(k){return '<option value="'+k+'">'+SOURCES[k]+'</option>';}).join('')+'</select>')+
          field('Montant','<input id="fMontant" inputmode="decimal" placeholder="0" required>')+
          field('Devise','<select id="fDevise" required></select>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="mSave" style="width:auto">Enregistrer</button><button class="btn" type="button" data-cancel="formCard">Annuler</button></div></form>'+
      '</div>'+

      // formulaire : clôture
      '<div class="card hidden" id="closeCard" data-ecriture style="margin-bottom:16px">'+
        '<h3 style="margin:0 0 6px">Clôturer la session</h3>'+
        '<p style="margin:0 0 12px;color:var(--muted);font-size:13px">Saisis le solde réellement compté. L’écart avec le solde théorique est conservé pour le suivi.</p>'+
        '<form id="cForm"><div class="formgrid">'+
          field('Solde compté (USD)','<input id="cSolde" inputmode="decimal" required>')+
          field('Solde théorique (USD)','<input id="cTheo" disabled>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="cSave" style="width:auto">Clôturer</button><button class="btn" type="button" data-cancel="closeCard">Annuler</button></div></form>'+
      '</div>'+

      '<div class="toolbar"><span class="eyebrow" id="listCount">—</span></div>'+
      '<div class="card tight"><div class="table-wrap"><table>'+
        '<thead><tr><th>Heure</th><th>Libellé</th><th>Module</th><th>Nature</th><th>Sens</th><th class="num">Montant</th></tr></thead>'+
        '<tbody id="rows">'+h.loadingRow(6)+'</tbody></table></div></div>';

    function kpi(id,lab){ return '<div class="card kpi"><div class="lab">'+lab+'</div><div class="val tnum" id="'+id+'">—</div></div>'; }
    function field(lab,inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(sel){ return root.querySelector(sel); }
    function parseNum(v){ return parseFloat(String(v||'').replace(/\s/g,'').replace(',','.')); }
    function today(){ var d=new Date(); d.setMinutes(d.getMinutes()-d.getTimezoneOffset()); return d.toISOString().slice(0,10); }
    function fmtJour(j){ try{ return new Date(j+'T00:00:00').toLocaleDateString('fr-FR',{weekday:'short',day:'2-digit',month:'short',year:'numeric'}); }catch(e){ return j; } }
    function fmtHeure(t){ try{ return new Date(t).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'}); }catch(e){ return '—'; } }
    function usd(n){ return h.money(Math.round(n*100)/100, 'USD'); }

    // ----- état -----
    var devises=[], sessions=[], current=null, theorique=0, agentId=null;

    function toUsd(montant, deviseId){
      var d = devises.filter(function(x){return x.id===deviseId;})[0];
      var taux = d ? Number(d.taux||1) : 1;
      return Number(montant||0) / (taux || 1);
    }

    async function loadRefs(){
      var d = await store.select('devises', { eq:{ actif:true }, order:['id'] });
      devises = d.data||[];
      $('#fDevise').innerHTML = devises.map(function(x){return '<option value="'+x.id+'">'+esc(x.code)+'</option>';}).join('');
      // employé lié au compte connecté (facultatif)
      if(Elikya.user){
        var u = await store.select('users', { eq:{ auth_id:Elikya.user.id }, single:true });
        agentId = (u.data && u.data.id) || null;
      }
    }

    async function loadSessions(keepId){
      var res = await store.select('caisse_sessions', { embed:['users(nom)'], order:['jour', false], limit:60 });
      if(res.error){ h.toast('Erreur : '+res.error.message); sessions=[]; }
      else sessions = res.data||[];
      var sel = $('#sessSel');
      if(!sessions.length){
        sel.innerHTML = '<option value="">Aucune session — ouvre-en une</option>';
        current = null;
      } else {
        sel.innerHTML = sessions.map(function(s){
          return '<option value="'+s.id+'">'+esc(fmtJour(s.jour))+' · '+esc((s.users&&s.users.nom)||'Sans agent')+(s.statut==='cloturee'?' · clôturée':'')+'</option>';
        }).join('');
        var pick = keepId && sessions.filter(function(s){return s.id===keepId;})[0];
        if(!pick) pick = sessions.filter(function(s){return s.statut==='ouverte';})[0] || sessions[0];
        current = pick; sel.value = pick.id;
      }
      await loadMouvements();
    }

    async function loadMouvements(){
      var rows = $('#rows');
      updateHeader();
      if(!current){
        rows.innerHTML = '<tr><td colspan="6" style="padding:26px;text-align:center;color:var(--muted)">Aucune session de caisse.'+h.invite('Clique « Ouvrir une session ».')+'</td></tr>';
        setKpis(0,0,0); $('#listCount').textContent='—'; return;
      }
      rows.innerHTML = h.loadingRow(6);
      var res = await store.select('mouvements_caisse', { embed:['devises(code)'], eq:{ session_id:current.id }, order:['cree_le', false] });
      if(res.error){ rows.innerHTML = '<tr><td colspan="6" style="padding:22px;text-align:center;color:var(--crit)">Erreur : '+esc(res.error.message)+'</td></tr>'; return; }
      var data = res.data||[];
      var tin=0, tout=0;
      data.forEach(function(m){ var v=toUsd(m.montant,m.devise_id); if(m.sens==='entree') tin+=v; else tout+=v; });
      if(!data.length){
        rows.innerHTML = '<tr><td colspan="6" style="padding:26px;text-align:center;color:var(--muted)">Aucun mouvement dans cette session.</td></tr>';
      } else {
        rows.innerHTML = data.map(function(m){
          var inn = m.sens==='entree';
          return '<tr><td class="tnum">'+fmtHeure(m.cree_le)+'</td>'+
            '<td>'+esc(m.libelle)+'</td>'+
            '<td>'+esc(m.module||'—')+'</td>'+
            '<td>'+esc(SOURCES[m.source_type]||m.source_type||'—')+'</td>'+
            '<td>'+h.pill(inn?'Entrée':'Sortie', inn?'ok':'crit')+'</td>'+
            '<td class="num tnum" style="color:'+(inn?'var(--ok)':'var(--crit)')+'">'+(inn?'+':'−')+' '+h.money(m.montant, m.devises&&m.devises.code)+'</td></tr>';
        }).join('');
      }
      setKpis(Number(current.solde_ouverture||0), tin, tout);
      $('#listCount').textContent = data.length+' mouvement'+(data.length>1?'s':'');
    }

    function setKpis(ouv, tin, tout){
      theorique = ouv + tin - tout;
      $('#kOuv').textContent = usd(ouv);
      $('#kIn').textContent = usd(tin);
      $('#kOut').textContent = usd(tout);
      $('#kSolde').textContent = usd(theorique);
      var ec = $('#ecartCard');
      if(current && current.statut==='cloturee' && current.solde_cloture!=null){
        var diff = Number(current.solde_cloture) - theorique;
        var kind = Math.abs(diff) < 0.005 ? 'ok' : (diff>0 ? 'warn' : 'crit');
        var lab = Math.abs(diff) < 0.005 ? 'Caisse juste' : (diff>0 ? 'Excédent' : 'Manquant');
        ec.innerHTML = '<div style="display:flex;gap:14px;align-items:center;flex-wrap:wrap">'+
          '<b>Clôture</b><span>Solde compté : <b class="tnum">'+usd(Number(current.solde_cloture))+'</b></span>'+
          '<span>Écart : <b class="tnum">'+(diff>0?'+':'')+usd(diff)+'</b></span>'+h.pill(lab, kind)+'</div>';
        ec.classList.remove('hidden');
      } else ec.classList.add('hidden');
    }

    function updateHeader(){
      var open = current && current.statut==='ouverte';
      $('#sessPill').innerHTML = current ? h.pill(open?'Ouverte':'Clôturée', open?'ok':'neutral') : '';
      $('#closeBtn').classList.toggle('hidden', !open);
      $('#newBtn').disabled = !open;
      $('#newBtn').title = open ? '' : 'Ouvre ou sélectionne une session ouverte';
      if(!open){ $('#formCard').classList.add('hidden'); $('#closeCard').classList.add('hidden'); }
    }

    function show(id){ ['openCard','formCard','closeCard'].forEach(function(c){ $('#'+c).classList.toggle('hidden', c!==id || !$('#'+c).classList.contains('hidden')); }); }

    // ----- interactions -----
    root.addEventListener('click', function(e){
      var c = e.target.closest('[data-cancel]'); if(c) $('#'+c.dataset.cancel).classList.add('hidden');
    });
    $('#openBtn').addEventListener('click', function(){ $('#oJour').value = today(); show('openCard'); });
    $('#newBtn').addEventListener('click', function(){ if(current && current.statut==='ouverte') show('formCard'); });
    $('#closeBtn').addEventListener('click', function(){
      $('#cTheo').value = h.num(Math.round(theorique*100)/100);
      $('#cSolde').value = String(Math.round(theorique*100)/100);
      show('closeCard');
    });
    $('#refreshBtn').addEventListener('click', function(){ loadSessions(current && current.id); });
    $('#sessSel').addEventListener('change', function(){
      current = sessions.filter(function(s){return s.id===$('#sessSel').value;})[0] || null;
      loadMouvements();
    });

    $('#oForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var solde = parseNum($('#oSolde').value);
      if(isNaN(solde) || solde<0){ h.toast('Solde d’ouverture invalide'); return; }
      var jour = $('#oJour').value;
      // contrôle aussi fait ici, car hors ligne la base ne peut pas le vérifier
      var dup = sessions.filter(function(s){ return s.jour===jour && (s.agent_id||null)===agentId; })[0];
      if(dup){ h.toast('Une session existe déjà pour ce jour et cet agent'); return; }
      var btn=$('#oSave'); btn.disabled=true; btn.textContent='Ouverture…';
      var res = await store.insert('caisse_sessions', { jour: jour, solde_ouverture: solde, agent_id: agentId, statut: 'ouverte' });
      btn.disabled=false; btn.textContent='Ouvrir';
      if(res.error){
        h.toast(res.error.code==='23505' ? 'Une session existe déjà pour ce jour et cet agent' : 'Erreur : '+res.error.message);
        return;
      }
      h.toast('Session ouverte'+h.saved(res));
      $('#oForm').reset(); $('#openCard').classList.add('hidden');
      loadSessions(res.data.id);
    });

    $('#mForm').addEventListener('submit', async function(e){
      e.preventDefault();
      if(!current || current.statut!=='ouverte'){ h.toast('Aucune session ouverte'); return; }
      var montant = parseNum($('#fMontant').value);
      if(isNaN(montant) || montant<=0){ h.toast('Montant invalide'); return; }
      var btn=$('#mSave'); btn.disabled=true; btn.textContent='Enregistrement…';
      var payload = {
        session_id: current.id,
        sens: $('#fSens').value,
        libelle: $('#fLib').value.trim(),
        module: $('#fMod').value,
        source_type: $('#fSrc').value,
        montant: montant,
        devise_id: parseInt($('#fDevise').value,10),
        agent_id: agentId
      };
      var res = await store.insert('mouvements_caisse', payload);
      btn.disabled=false; btn.textContent='Enregistrer';
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast((payload.sens==='entree'?'Entrée':'Sortie')+' enregistrée'+h.saved(res));
      $('#mForm').reset(); $('#formCard').classList.add('hidden');
      loadMouvements();
    });

    $('#cForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var compte = parseNum($('#cSolde').value);
      if(isNaN(compte)){ h.toast('Solde compté invalide'); return; }
      if(!confirm('Clôturer la session du '+fmtJour(current.jour)+' ? Plus aucun mouvement ne pourra y être ajouté.')) return;
      var btn=$('#cSave'); btn.disabled=true; btn.textContent='Clôture…';
      var res = await store.update('caisse_sessions', current.id, { solde_cloture: compte, statut: 'cloturee' });
      btn.disabled=false; btn.textContent='Clôturer';
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast('Session clôturée'+h.saved(res));
      $('#closeCard').classList.add('hidden');
      loadSessions(current.id);
    });

    await loadRefs();
    await loadSessions();
  }
});
