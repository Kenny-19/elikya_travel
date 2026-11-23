/* modules/clients.js — Clients (site direction) : fiches + chiffre d'affaires cumulé.
   CA cumulé = dossiers voyage + commandes fourniture, hors annulés, en USD (CDF ÷ taux).
   Même règles que l'app agents (agents/lib/ui/pages/clients_page.dart). */
Elikya.registerModule({
  id: 'clients',
  label: 'Clients',
  group: 'Référentiel',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var TYPES = { particulier:'Particulier', entreprise:'Entreprise' };
    var SEGMENTS = ['', 'VIP', 'Grand compte', 'Régulier', 'Prospect'];
    var clients = [], stats = {}, editId = null;

    function usd(n){ return h.money(Math.round((Number(n)||0)*100)/100, 'USD'); }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function field(lab, inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }
    function kpi(lab, val, sub){ return '<div class="card kpi"><div class="lab">'+lab+'</div><div class="val tnum">'+val+'</div>'+(sub ? '<div class="sub">'+sub+'</div>' : '')+'</div>'; }
    function st(c){ return stats[c.id] || { dossiers:0, commandes:0, ca:0 }; }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Référentiel</div><h1 class="pf">Clients</h1>'+
        '<p>Fiches clients et chiffre d’affaires cumulé (voyage + fourniture, hors annulés, en USD).</p></div>'+
        '<button class="btn primary" id="newBtn" data-ecriture style="width:auto">＋ Nouveau client</button></div>'+
      '<div class="row k4" id="kpis" style="margin-bottom:16px"></div>'+
      '<div class="card hidden" id="fCard" data-ecriture style="margin-bottom:16px"><h3 id="fTitle"></h3>'+
        '<form id="fForm"><div class="formgrid">'+
          field('Nom','<input id="fNom" required>')+
          field('Type','<select id="fType">'+Object.keys(TYPES).map(function(k){ return '<option value="'+k+'">'+TYPES[k]+'</option>'; }).join('')+'</select>')+
          field('Téléphone','<input id="fTel" inputmode="tel" placeholder="+243…">')+
          field('Ville','<input id="fVille">')+
          field('E-mail','<input id="fEmail" type="email">')+
          field('Segment','<select id="fSeg">'+SEGMENTS.map(function(s){ return '<option value="'+s+'">'+(s || '—')+'</option>'; }).join('')+'</select>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="fSave" style="width:auto">Enregistrer</button>'+
        '<button class="btn" type="button" id="fCancel">Annuler</button></div></form></div>'+
      '<div class="toolbar">'+
        '<div class="field" style="margin:0;min-width:260px"><input id="q" placeholder="Rechercher (nom, téléphone, ville…)"></div>'+
        '<div class="field" style="margin:0"><select id="tSel"><option value="">Tous types</option>'+
          Object.keys(TYPES).map(function(k){ return '<option value="'+k+'">'+TYPES[k]+'</option>'; }).join('')+'</select></div>'+
        '<div class="field" style="margin:0"><select id="triSel"><option value="nom">Tri par nom</option><option value="ca">Tri par CA</option></select></div>'+
        '<span class="eyebrow" id="count">—</span>'+
        '<button class="btn" id="refreshBtn" style="margin-left:auto">↻ Rafraîchir</button>'+
      '</div>'+
      '<div class="card tight"><div class="table-wrap"><table><thead><tr><th>Nom</th><th>Type</th><th>Téléphone</th><th>Ville</th><th>Segment</th>'+
        '<th class="num">Dossiers</th><th class="num">Commandes</th><th class="num">CA cumulé</th><th></th></tr></thead>'+
        '<tbody id="rows">'+h.loadingRow(9)+'</tbody></table></div></div>';

    async function load(){
      var r = await Promise.all([
        store.select('clients', { order:['nom'] }),
        store.select('devises', {}),
        store.select('dossiers', { limit:20000 }),
        store.select('commandes', { limit:20000 })
      ]);
      var err = r.filter(function(x){ return x.error; })[0];
      if(err) h.toast('Erreur : '+err.error.message);
      clients = r[0].data||[];
      stats = S.statsClients(r[2].data||[], r[3].data||[], r[1].data||[]);
      draw();
    }

    function draw(){
      var q = $('#q').value.trim().toLowerCase(), type = $('#tSel').value;
      var list = clients.filter(function(c){
        if(type && c.type !== type) return false;
        if(!q) return true;
        return ['nom','telephone','ville','email','segment'].some(function(k){ return String(c[k]||'').toLowerCase().indexOf(q) >= 0; });
      });
      if($('#triSel').value === 'ca') list.sort(function(a, b){ return st(b).ca - st(a).ca; });

      var total = clients.reduce(function(a, c){ return a + st(c).ca; }, 0);
      var top = clients.slice().sort(function(a, b){ return st(b).ca - st(a).ca; })[0];
      $('#kpis').innerHTML = kpi('Clients', clients.length)+
        kpi('Entreprises', clients.filter(function(c){ return c.type === 'entreprise'; }).length)+
        kpi('CA cumulé', usd(total))+
        kpi('Meilleur client', top && st(top).ca ? esc(top.nom) : '—', top && st(top).ca ? usd(st(top).ca) : '');
      $('#count').textContent = list.length+' client'+(list.length > 1 ? 's' : '');
      $('#rows').innerHTML = list.length ? list.map(function(c){
        var s = st(c);
        return '<tr><td><b>'+esc(c.nom)+'</b></td><td>'+(c.type === 'entreprise' ? h.pill('Entreprise','info') : h.pill('Particulier','neutral'))+'</td>'+
          '<td class="tnum">'+esc(c.telephone||'—')+'</td><td>'+esc(c.ville||'—')+'</td><td>'+(c.segment ? h.pill(esc(c.segment),'warn') : '—')+'</td>'+
          '<td class="num tnum">'+s.dossiers+'</td><td class="num tnum">'+s.commandes+'</td><td class="num tnum"><b>'+usd(s.ca)+'</b></td>'+
          '<td><button class="lnk" data-ecriture data-edit="'+c.id+'">Modifier</button></td></tr>';
      }).join('') : '<tr><td colspan="9" style="padding:26px;text-align:center;color:var(--muted)">'+
        (clients.length ? 'Aucun client ne correspond.' : 'Aucun client.'+h.invite('Clique « Nouveau client ».')+'')+'</td></tr>';
    }

    function openForm(c){
      editId = c ? c.id : null;
      $('#fTitle').textContent = c ? 'Modifier '+c.nom : 'Nouveau client';
      $('#fNom').value = c ? c.nom : '';
      $('#fType').value = c && TYPES[c.type] ? c.type : 'particulier';
      $('#fTel').value = c ? (c.telephone||'') : '';
      $('#fVille').value = c ? (c.ville||'') : 'Lubumbashi';
      $('#fEmail').value = c ? (c.email||'') : '';
      $('#fSeg').value = c && SEGMENTS.indexOf(c.segment||'') >= 0 ? (c.segment||'') : '';
      $('#fCard').classList.remove('hidden');
      $('#fNom').focus();
    }

    $('#fForm').addEventListener('submit', async function(e){
      e.preventDefault();
      function opt(id){ var v = $(id).value.trim(); return v || null; }
      var row = { nom:$('#fNom').value.trim(), type:$('#fType').value, telephone:opt('#fTel'), ville:opt('#fVille'),
                  email:opt('#fEmail'), segment:$('#fSeg').value || null };
      if(!row.nom){ h.toast('Nom requis'); return; }
      var btn = $('#fSave'); btn.disabled = true; btn.textContent = 'Enregistrement…';
      var me = Elikya.profile && Elikya.profile.user_id;
      var res = editId ? await store.update('clients', editId, row) : await store.insert('clients', Object.assign({ cree_par: me || null }, row));
      btn.disabled = false; btn.textContent = 'Enregistrer';
      if(res.error){ h.toast('Erreur : '+res.error.message); return; }
      h.toast('Client '+row.nom+' enregistré'+h.saved(res));
      $('#fCard').classList.add('hidden');
      load();
    });

    $('#newBtn').addEventListener('click', function(){ openForm(null); });
    $('#fCancel').addEventListener('click', function(){ $('#fCard').classList.add('hidden'); });
    $('#refreshBtn').addEventListener('click', load);
    ['#q','#tSel','#triSel'].forEach(function(s){ $(s).addEventListener(s === '#q' ? 'input' : 'change', draw); });
    $('#rows').addEventListener('click', function(e){
      var b = e.target.closest('[data-edit]');
      if(b) openForm(clients.filter(function(c){ return c.id === b.dataset.edit; })[0]);
    });

    await load();
  }
});
