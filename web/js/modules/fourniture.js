/* modules/fourniture.js — Fourniture (site direction) : catalogue + commandes clients.
   Même règles que l'app agents (agents/lib/ui/pages/fourniture_page.dart) :
   le stock est un inventaire RELEVÉ (pas de déduction automatique à la livraison) ;
   « réservé » = lignes des commandes à livrer, « disponible » = stock − réservé. Montants en USD. */
Elikya.registerModule({
  id: 'fourniture',
  label: 'Fourniture',
  group: 'Activités',
  async render(root){
    var store = Elikya.data, h = Elikya.h, S = Elikya.stats;
    var CATEGORIES = ['Tuyauterie','Sécurité/EPI','Informatique','Ménager','Technique','Autre'];
    var STATUTS = { brouillon:['Brouillon','info'], a_livrer:['À livrer','warn'], livree:['Livrée','ok'], annulee:['Annulée','crit'] };
    var vue = 'catalogue';
    var produits = [], commandes = [], lignes = [], clients = [], editId = null;

    function usd(n){ return h.money(Math.round((Number(n)||0)*100)/100, 'USD'); }
    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function parseNum(v){ return parseFloat(String(v||'').replace(/\s/g,'').replace(',','.')); }
    function field(lab, inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }
    function kpi(lab, val){ return '<div class="card kpi"><div class="lab">'+lab+'</div><div class="val tnum">'+val+'</div></div>'; }
    function empty(cols, txt){ return '<tr><td colspan="'+cols+'" style="padding:26px;text-align:center;color:var(--muted)">'+txt+'</td></tr>'; }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Module · Suivi</div><h1 class="pf">Fourniture</h1>'+
        '<p>Catalogue et commandes clients. Stock = inventaire relevé ; montants en USD.</p></div>'+
        '<div class="toolbar" style="margin:0"><div class="seg" id="seg"><button data-v="catalogue">Catalogue</button><button data-v="commandes">Commandes</button></div>'+
        '<button class="btn" id="refreshBtn">↻</button><button class="btn gold" id="newBtn" style="width:auto"></button></div></div>'+
      '<div class="row k4" id="kpis" style="margin-bottom:16px"></div>'+

      // formulaire produit (création / modification-inventaire)
      '<div class="card hidden" id="pCard" style="margin-bottom:16px"><h3 id="pTitle"></h3>'+
        '<form id="pForm"><div class="formgrid">'+
          field('Référence','<input id="pRef" placeholder="Ex. TUY-110" required>')+
          field('Désignation','<input id="pDes" required>')+
          field('Catégorie','<select id="pCat">'+CATEGORIES.map(function(c){ return '<option>'+c+'</option>'; }).join('')+'</select>')+
          field('Unité','<input id="pUnite" value="pièce">')+
          field('Stock relevé','<input id="pStock" inputmode="numeric" value="0" required>')+
          field('Seuil d’alerte','<input id="pSeuil" inputmode="numeric" value="5" required>')+
          field('Prix unitaire (USD)','<input id="pPrix" inputmode="decimal" required>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn gold" type="submit" id="pSave" style="width:auto">Enregistrer</button>'+
        '<button class="btn" type="button" data-cancel="pCard">Annuler</button></div></form></div>'+

      // formulaire commande
      '<div class="card hidden" id="cCard" style="margin-bottom:16px"><h3>Nouvelle commande</h3>'+
        '<form id="cForm"><div class="formgrid">'+
          field('Client','<select id="cClient" required></select>')+
          field('Statut','<select id="cStatut"><option value="a_livrer">À livrer</option><option value="brouillon">Brouillon</option></select>')+
        '</div><h3 style="margin:16px 0 8px;font-size:13px">Lignes</h3><div id="cLignes"></div>'+
        '<div class="toolbar" style="margin:8px 0 0"><button class="btn" type="button" id="addLigne">＋ Ajouter une ligne</button>'+
        '<b class="tnum" id="cTotal" style="margin-left:auto;font-size:16px"></b></div>'+
        '<div class="toolbar" style="margin:16px 0 0"><button class="btn gold" type="submit" id="cSave" style="width:auto">Enregistrer</button>'+
        '<button class="btn" type="button" data-cancel="cCard">Annuler</button></div></form></div>'+

      '<div class="card tight"><div class="table-wrap"><table><thead id="thead"></thead><tbody id="rows">'+h.loadingRow(9)+'</tbody></table></div></div>';

    async function load(){
      var r = await Promise.all([
        store.select('produits', { order:['ref'] }),
        store.select('commandes', { embed:['clients(nom)'], order:['cree_le', false], limit:300 }),
        store.select('commande_lignes', { limit:3000 }),
        store.select('clients', { order:['nom'] })
      ]);
      var err = r.filter(function(x){ return x.error; })[0];
      if(err) h.toast('Erreur : '+err.error.message);
      produits = (r[0].data||[]).filter(function(p){ return p.actif !== false; });
      commandes = r[1].data||[]; lignes = r[2].data||[]; clients = r[3].data||[];
      $('#cClient').innerHTML = clients.map(function(c){ return '<option value="'+c.id+'">'+esc(c.nom)+'</option>'; }).join('');
      draw();
    }

    function draw(){
      root.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('on', b.dataset.v === vue); });
      $('#newBtn').textContent = vue === 'catalogue' ? '＋ Nouveau produit' : '＋ Nouvelle commande';
      if(vue === 'catalogue') drawCatalogue(); else drawCommandes();
    }

    function etat(p, dispo){
      var st = Number(p.stock)||0;
      if(st <= 0) return h.pill('Rupture','crit');
      if(dispo < 0) return h.pill('Insuffisant','crit');
      if(st <= (Number(p.seuil_alerte)||0)) return h.pill('Sous le seuil','warn');
      return h.pill('OK','ok');
    }

    function drawCatalogue(){
      var res = S.reservations(commandes, lignes), valeur = 0, alertes = 0, ruptures = 0;
      produits.forEach(function(p){
        var st = Number(p.stock)||0; valeur += st * (Number(p.prix)||0);
        if(st <= 0) ruptures++; else if(st <= (Number(p.seuil_alerte)||0)) alertes++;
      });
      $('#kpis').innerHTML = kpi('Produits', produits.length)+kpi('Valeur du stock', usd(valeur))+kpi('Sous le seuil', alertes)+kpi('Ruptures', ruptures);
      $('#thead').innerHTML = '<tr><th>Réf.</th><th>Désignation</th><th>Catégorie</th><th class="num">Stock</th><th class="num">Réservé</th><th class="num">Disponible</th><th class="num">Prix</th><th>État</th><th></th></tr>';
      $('#rows').innerHTML = produits.length ? produits.map(function(p){
        var st = Number(p.stock)||0, re = res[p.id]||0, dispo = st - re;
        return '<tr><td><span class="mono-ref">'+esc(p.ref)+'</span></td><td>'+esc(p.designation)+'</td><td>'+esc(p.categorie||'—')+'</td>'+
          '<td class="num tnum">'+st+' '+esc(p.unite||'')+'</td><td class="num tnum">'+(re||'—')+'</td>'+
          '<td class="num tnum" style="'+(dispo < 0 ? 'color:var(--crit);font-weight:700' : '')+'">'+dispo+'</td>'+
          '<td class="num tnum">'+usd(p.prix)+'</td><td>'+etat(p, dispo)+'</td>'+
          '<td><button class="lnk" data-edit="'+p.id+'">Modifier</button></td></tr>';
      }).join('') : empty(9, 'Aucun produit. Clique « Nouveau produit ».');
    }

    function drawCommandes(){
      var nb = {}; lignes.forEach(function(l){ nb[l.commande_id] = (nb[l.commande_id]||0) + 1; });
      var aLivrer = commandes.filter(function(c){ return c.statut === 'a_livrer'; });
      var sum = function(list){ return list.reduce(function(a, c){ return a + (Number(c.total)||0); }, 0); };
      $('#kpis').innerHTML = kpi('Commandes', commandes.length)+kpi('À livrer', aLivrer.length)+
        kpi('Montant à livrer', usd(sum(aLivrer)))+kpi('Total (hors annulées)', usd(sum(commandes.filter(function(c){ return c.statut !== 'annulee'; }))));
      $('#thead').innerHTML = '<tr><th>Réf.</th><th>Client</th><th>Date</th><th class="num">Lignes</th><th class="num">Total</th><th>Statut</th></tr>';
      $('#rows').innerHTML = commandes.length ? commandes.map(function(c){
        var st = STATUTS[c.statut] || [c.statut,'neutral'];
        var statut = (c.statut === 'brouillon' || c.statut === 'a_livrer')
          ? '<select data-statut="'+c.id+'" style="font:inherit;font-size:12px;padding:3px 6px;border:1px solid var(--line);border-radius:7px;background:var(--panel2);color:var(--ink)">'+
              Object.keys(STATUTS).map(function(k){ return '<option value="'+k+'"'+(k === c.statut ? ' selected' : '')+'>'+STATUTS[k][0]+'</option>'; }).join('')+'</select>'
          : h.pill(st[0], st[1]);
        var d = c.cree_le ? new Date(c.cree_le).toLocaleDateString('fr-FR') : '—';
        return '<tr><td><span class="mono-ref">'+esc(c.ref)+'</span></td><td>'+esc((c.clients && c.clients.nom) || '—')+'</td><td class="tnum">'+d+'</td>'+
          '<td class="num tnum">'+(nb[c.id]||0)+'</td><td class="num tnum"><b>'+usd(c.total)+'</b></td><td>'+statut+'</td></tr>';
      }).join('') : empty(6, 'Aucune commande. Clique « Nouvelle commande ».');
    }

    // ----- produit -----
    function openProduit(p){
      editId = p ? p.id : null;
      $('#cCard').classList.add('hidden');
      $('#pTitle').textContent = p ? 'Modifier '+p.ref+' · inventaire' : 'Nouveau produit';
      $('#pRef').value = p ? p.ref : ''; $('#pRef').disabled = !!p;
      $('#pDes').value = p ? p.designation : '';
      $('#pCat').value = p && CATEGORIES.indexOf(p.categorie) >= 0 ? p.categorie : CATEGORIES[0];
      $('#pUnite').value = p ? (p.unite||'') : 'pièce';
      $('#pStock').value = p ? (p.stock||0) : 0;
      $('#pSeuil').value = p ? (p.seuil_alerte||0) : 5;
      $('#pPrix').value = p ? p.prix : '';
      $('#pCard').classList.remove('hidden');
      $('#pDes').focus();
    }

    $('#pForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var stock = parseInt($('#pStock').value, 10), seuil = parseInt($('#pSeuil').value, 10), prix = parseNum($('#pPrix').value);
      if(!(stock >= 0) || !(seuil >= 0)){ h.toast('Stock et seuil : nombres entiers ≥ 0'); return; }
      if(isNaN(prix) || prix < 0){ h.toast('Prix invalide'); return; }
      var row = { designation:$('#pDes').value.trim(), categorie:$('#pCat').value, unite:$('#pUnite').value.trim() || null,
                  stock:stock, seuil_alerte:seuil, prix:prix };
      var ref = $('#pRef').value.trim().toUpperCase();
      if(!editId && produits.some(function(p){ return String(p.ref).toUpperCase() === ref; })){ h.toast('Cette référence existe déjà'); return; }
      var btn = $('#pSave'); btn.disabled = true; btn.textContent = 'Enregistrement…';
      var res = editId ? await store.update('produits', editId, row) : await store.insert('produits', Object.assign({ ref:ref }, row));
      btn.disabled = false; btn.textContent = 'Enregistrer';
      if(res.error){ h.toast(res.error.code === '23505' ? 'Cette référence existe déjà' : 'Erreur : '+res.error.message); return; }
      h.toast('Produit '+(editId ? $('#pRef').value : ref)+' enregistré'+h.saved(res));
      $('#pCard').classList.add('hidden');
      load();
    });

    // ----- commande -----
    function ligneHtml(){
      return '<div class="formgrid ligne" style="grid-template-columns:3fr 1fr 1fr auto auto;align-items:end;margin-bottom:8px">'+
        field('Produit','<select class="lProd">'+produits.map(function(p){ return '<option value="'+p.id+'" data-prix="'+p.prix+'">'+esc(p.ref+' · '+p.designation)+'</option>'; }).join('')+'</select>')+
        field('Quantité','<input class="lQte" inputmode="numeric" value="1">')+
        field('Prix unit.','<input class="lPrix" inputmode="decimal" value="'+(produits[0] ? produits[0].prix : 0)+'">')+
        '<div class="field tnum lTot" style="min-width:90px;text-align:right;padding-bottom:10px"></div>'+
        '<div class="field"><button class="btn" type="button" data-rm title="Retirer la ligne">✕</button></div></div>';
    }
    function lignesForm(){
      return Array.prototype.map.call(root.querySelectorAll('#cLignes .ligne'), function(el){
        return { el:el, produit_id:el.querySelector('.lProd').value, quantite:parseInt(el.querySelector('.lQte').value, 10),
                 prix:parseNum(el.querySelector('.lPrix').value) };
      });
    }
    function recalc(){
      var total = 0;
      lignesForm().forEach(function(l){
        var t = (l.quantite > 0 && l.prix >= 0) ? l.quantite * l.prix : 0; total += t;
        l.el.querySelector('.lTot').textContent = usd(t);
      });
      $('#cTotal').textContent = 'Total : '+usd(total);
      var rm = root.querySelectorAll('#cLignes [data-rm]');
      rm.forEach(function(b){ b.disabled = rm.length === 1; });
      return Math.round(total*100)/100;
    }
    function openCommande(){
      if(!clients.length || !produits.length){ h.toast('Il faut au moins un client et un produit'); return; }
      $('#pCard').classList.add('hidden');
      $('#cForm').reset();
      $('#cLignes').innerHTML = ligneHtml();
      recalc();
      $('#cCard').classList.remove('hidden');
    }
    $('#addLigne').addEventListener('click', function(){ $('#cLignes').insertAdjacentHTML('beforeend', ligneHtml()); recalc(); });
    $('#cLignes').addEventListener('click', function(e){ var b = e.target.closest('[data-rm]'); if(b){ b.closest('.ligne').remove(); recalc(); } });
    $('#cLignes').addEventListener('input', recalc);
    $('#cLignes').addEventListener('change', function(e){
      if(e.target.classList.contains('lProd')){
        var opt = e.target.selectedOptions[0];
        e.target.closest('.ligne').querySelector('.lPrix').value = opt ? opt.dataset.prix : 0;
      }
      recalc();
    });

    $('#cForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var ls = lignesForm();
      if(ls.some(function(l){ return !(l.quantite > 0) || isNaN(l.prix) || l.prix < 0; })){ h.toast('Chaque ligne : quantité > 0 et prix valide'); return; }
      var btn = $('#cSave'); btn.disabled = true; btn.textContent = 'Enregistrement…';
      var ref = 'CMD-'+String(Date.now()).slice(7);
      var cmd = await store.insert('commandes', { ref:ref, client_id:$('#cClient').value, statut:$('#cStatut').value, total:recalc() });
      if(cmd.error){ btn.disabled = false; btn.textContent = 'Enregistrer'; h.toast('Erreur : '+cmd.error.message); return; }
      for(var i = 0; i < ls.length; i++){
        var r = await store.insert('commande_lignes', { commande_id:cmd.data.id, produit_id:ls[i].produit_id, quantite:ls[i].quantite, prix_unitaire:ls[i].prix });
        if(r.error) h.toast('Ligne non enregistrée : '+r.error.message);
      }
      btn.disabled = false; btn.textContent = 'Enregistrer';
      h.toast('Commande '+ref+' enregistrée'+h.saved(cmd));
      $('#cCard').classList.add('hidden');
      load();
    });

    // ----- interactions -----
    $('#seg').addEventListener('click', function(e){
      var b = e.target.closest('button[data-v]'); if(!b) return;
      vue = b.dataset.v; $('#pCard').classList.add('hidden'); $('#cCard').classList.add('hidden'); draw();
    });
    $('#newBtn').addEventListener('click', function(){ if(vue === 'catalogue') openProduit(null); else openCommande(); });
    $('#refreshBtn').addEventListener('click', load);
    root.addEventListener('click', function(e){
      var c = e.target.closest('[data-cancel]'); if(c) $('#'+c.dataset.cancel).classList.add('hidden');
      var ed = e.target.closest('[data-edit]');
      if(ed) openProduit(produits.filter(function(p){ return p.id === ed.dataset.edit; })[0]);
    });
    $('#rows').addEventListener('change', async function(e){
      var s = e.target.closest('[data-statut]'); if(!s) return;
      s.disabled = true;
      var res = await store.update('commandes', s.dataset.statut, { statut:s.value });
      if(res.error){ h.toast('Erreur : '+res.error.message); s.disabled = false; return; }
      h.toast('Statut : '+STATUTS[s.value][0]+h.saved(res));
      load();
    });

    await load();
  }
});
