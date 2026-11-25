/* modules/admin.js — Administration (SUPER ADMIN uniquement, entrée cachée #admin).
   - Comptes : créer le compte d'un agent (e-mail + mot de passe + rôle), changer son rôle,
     réinitialiser son mot de passe, désactiver / réactiver. Passe par la fonction serveur
     Supabase « admin-comptes » (supabase/functions/admin-comptes) : la clé secrète n'est
     jamais dans le site.
   - Rôles : choisir les modules visibles par chaque rôle (table roles, RLS super admin).
   Absent du menu ; accès : Ctrl+Maj+A, 5 clics sur le logo, ou …/#admin (cf. app.js). */
Elikya.registerModule({
  id: 'admin',
  label: 'Administration',
  group: 'Système',
  hidden: true,       // jamais dans le menu
  superAdmin: true,   // app.js renvoie à l'accueil si le compte n'est pas super admin
  async render(root){
    var store = Elikya.data, h = Elikya.h;
    var MODULES = [['voyage','Voyage'],['location','Location'],['caisse','Caisse'],['momo','Mobile Money'],['fourniture','Fourniture'],['clients','Clients']];
    var vue = 'comptes', comptes = [], roles = [];

    function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
    function $(s){ return root.querySelector(s); }
    function field(lab, inner){ return '<div class="field"><label>'+lab+'</label>'+inner+'</div>'; }
    function quand(t){ if(!t) return 'jamais'; try{ return new Date(t).toLocaleString('fr-FR',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}); }catch(e){ return t; } }
    function motDePasse(){
      var abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789', b = new Uint8Array(12), s = '';
      crypto.getRandomValues(b); for(var i = 0; i < b.length; i++) s += abc[b[i] % abc.length];
      return s.slice(0,4)+'-'+s.slice(4,8)+'-'+s.slice(8);
    }
    var rolesAttribuables = function(){ return roles.filter(function(r){ return r.code !== 'superadmin'; }); };

    // appel de la fonction serveur, avec des messages d'erreur lisibles
    async function call(action, payload){
      var r;
      try{ r = await Elikya.db.functions.invoke('admin-comptes', { body: Object.assign({ action:action }, payload||{}) }); }
      catch(e){ r = { error:e }; }
      if(r.error){
        var msg = r.error.message || String(r.error);
        try{ var j = await r.error.context.json(); if(j && j.error) msg = j.error; }catch(e){}
        if(/failed to send|fetch|not found|404/i.test(msg))
          msg = 'Fonction « admin-comptes » injoignable : est-elle déployée dans Supabase ? (voir docs/super-admin.md)';
        return { error: msg };
      }
      if(r.data && r.data.error) return { error: r.data.error };
      return { data: r.data };
    }

    root.innerHTML =
      '<div class="phead"><div><div class="eyebrow">Système · Super admin</div><h1 class="pf">Administration</h1>'+
        '<p>Comptes des agents et droits des rôles. Visible uniquement par le super administrateur.</p></div>'+
        '<div class="toolbar" style="margin:0"><div class="seg" id="seg"><button data-v="comptes">Comptes</button><button data-v="roles">Rôles</button></div>'+
        '<button class="btn" id="refreshBtn">↻</button><button class="btn primary" id="newBtn" style="width:auto">＋ Nouveau compte</button></div></div>'+
      '<div class="card hidden" id="resultCard" style="margin-bottom:16px;border-color:var(--ok)"></div>'+
      '<div class="card hidden" id="fCard" style="margin-bottom:16px"><h3>Nouveau compte agent</h3>'+
        '<form id="fForm" autocomplete="off"><div class="formgrid">'+
          field('Nom complet','<input id="fNom" required>')+
          field('E-mail (identifiant de connexion)','<input id="fEmail" type="email" required>')+
          field('Téléphone','<input id="fTel" inputmode="tel" placeholder="+243…">')+
          field('Rôle','<select id="fRole" required></select>')+
          field('Mot de passe (à transmettre à l’agent)','<div style="display:flex;gap:8px"><input id="fPass" required minlength="8" style="flex:1">'+
            '<button class="btn" type="button" id="genBtn" title="Générer">⟳</button></div>')+
        '</div><div class="toolbar" style="margin:16px 0 0"><button class="btn primary" type="submit" id="fSave" style="width:auto">Créer le compte</button>'+
        '<button class="btn" type="button" id="fCancel">Annuler</button></div></form></div>'+
      '<div id="body"></div>';

    async function load(){
      var r = await store.select('roles', { order:['id'] });
      roles = r.data || [];
      $('#fRole').innerHTML = rolesAttribuables().map(function(x){ return '<option value="'+x.id+'">'+esc(x.nom)+'</option>'; }).join('');
      if(vue === 'comptes'){
        $('#body').innerHTML = '<div class="card tight"><div class="table-wrap"><table><tbody>'+h.loadingRow(7)+'</tbody></table></div></div>';
        var c = await call('lister');
        if(c.error){ $('#body').innerHTML = '<div class="card" style="color:var(--crit)">'+esc(c.error)+'</div>'; return; }
        comptes = c.data.comptes || [];
      }
      draw();
    }

    function draw(){
      root.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('on', b.dataset.v === vue); });
      $('#newBtn').classList.toggle('hidden', vue !== 'comptes');
      if(vue === 'comptes') drawComptes(); else drawRoles();
    }

    function drawComptes(){
      var moi = Elikya.profile && Elikya.profile.user_id;
      $('#body').innerHTML = '<div class="card tight"><div class="table-wrap"><table><thead><tr><th>Nom</th><th>E-mail</th><th>Rôle</th>'+
        '<th>Connexion</th><th>Dernière connexion</th><th>Statut</th><th></th></tr></thead><tbody>'+
        (comptes.length ? comptes.map(function(u){
          var sa = u.roles && u.roles.code === 'superadmin', lui = u.id === moi;
          var role = sa || lui ? esc(u.roles && u.roles.nom || '—')
            : '<select data-role="'+u.id+'" style="font:inherit;font-size:12.5px;padding:4px 6px;border:1px solid var(--line);border-radius:8px;background:var(--panel2);color:var(--ink)">'+
                rolesAttribuables().map(function(r){ return '<option value="'+r.id+'"'+(r.id === u.role_id ? ' selected' : '')+'>'+esc(r.nom)+'</option>'; }).join('')+'</select>';
          return '<tr><td><b>'+esc(u.nom)+'</b>'+(lui ? ' <span class="pill info">vous</span>' : '')+'</td><td>'+esc(u.email||'—')+'</td><td>'+role+'</td>'+
            '<td>'+(u.compte ? h.pill('Compte relié','ok') : h.pill('Sans compte','neutral'))+'</td>'+
            '<td class="tnum">'+esc(quand(u.derniere_connexion))+'</td>'+
            '<td>'+(u.actif ? h.pill('Actif','ok') : h.pill('Désactivé','crit'))+'</td>'+
            '<td style="white-space:nowrap">'+(u.compte ? '<button class="lnk" data-mdp="'+u.id+'">Mot de passe</button>' : '')+
              (lui ? '' : ' &nbsp;<button class="lnk" data-actif="'+u.id+'" data-val="'+(u.actif ? '0' : '1')+'">'+(u.actif ? 'Désactiver' : 'Réactiver')+'</button>')+'</td></tr>';
        }).join('') : '<tr><td colspan="7" style="padding:26px;text-align:center;color:var(--muted)">Aucune fiche employé.</td></tr>')+
        '</tbody></table></div></div>'+
        '<p style="color:var(--muted);font-size:12.5px;margin-top:10px">Un compte désactivé ne peut plus se connecter (site ni app) et ne voit plus aucune donnée. '+
        'Les fiches « Sans compte » viennent du jeu de départ : créez-leur un compte avec le même e-mail pour les relier.</p>';
    }

    function drawRoles(){
      $('#body').innerHTML = '<div class="card tight"><div class="table-wrap"><table><thead><tr><th>Rôle</th>'+
        MODULES.map(function(m){ return '<th style="text-align:center">'+m[1]+'</th>'; }).join('')+'<th></th></tr></thead><tbody>'+
        roles.map(function(r){
          var p = r.permissions || {}, tout = p.all === true;
          return '<tr data-r="'+r.id+'"><td><b>'+esc(r.nom)+'</b>'+(r.code ? ' <span style="color:var(--faint);font-size:11.5px">'+esc(r.code)+'</span>' : '')+'</td>'+
            MODULES.map(function(m){
              return '<td style="text-align:center">'+(tout ? '<span title="Accès complet" style="color:var(--ok);font-weight:800">✓</span>'
                : '<input type="checkbox" data-mod="'+m[0]+'"'+(p[m[0]] === true ? ' checked' : '')+' style="width:17px;height:17px;accent-color:var(--accent)">')+'</td>';
            }).join('')+
            '<td>'+(tout ? '<span style="color:var(--faint);font-size:12px">accès complet</span>' : '<button class="btn" data-save="'+r.id+'" style="padding:6px 12px;font-size:12.5px">Enregistrer</button>')+'</td></tr>';
        }).join('')+'</tbody></table></div></div>'+
        '<p style="color:var(--muted);font-size:12.5px;margin-top:10px">Les agents voient les nouveaux droits à leur prochaine connexion à l’application. '+
        'La direction et le super administrateur ont un accès complet (non modifiable ici).</p>';
    }

    // ----- création -----
    function ouvrirForm(){
      $('#resultCard').classList.add('hidden');
      $('#fForm').reset(); $('#fPass').value = motDePasse();
      $('#fCard').classList.remove('hidden'); $('#fNom').focus();
    }
    $('#genBtn').addEventListener('click', function(){ $('#fPass').value = motDePasse(); });
    $('#fCancel').addEventListener('click', function(){ $('#fCard').classList.add('hidden'); });
    $('#fForm').addEventListener('submit', async function(e){
      e.preventDefault();
      var payload = { nom:$('#fNom').value.trim(), email:$('#fEmail').value.trim().toLowerCase(), telephone:$('#fTel').value.trim(),
                      role_id:parseInt($('#fRole').value, 10), password:$('#fPass').value };
      if(payload.password.length < 8){ h.toast('Mot de passe : 8 caractères minimum'); return; }
      var btn = $('#fSave'); btn.disabled = true; btn.textContent = 'Création…';
      var r = await call('creer', payload);
      btn.disabled = false; btn.textContent = 'Créer le compte';
      if(r.error){ h.toast(r.error); return; }
      $('#fCard').classList.add('hidden');
      montrerIdentifiants(payload.nom, payload.email, payload.password, 'Compte créé');
      load();
    });

    function montrerIdentifiants(nom, email, pass, titre){
      var card = $('#resultCard');
      card.innerHTML = '<h3>'+esc(titre)+' · '+esc(nom)+'</h3>'+
        '<p style="margin:0 0 10px;color:var(--muted);font-size:13px">Transmets ces identifiants à l’agent (de vive voix ou par message privé). '+
        'Le mot de passe n’est affiché qu’une fois.</p>'+
        '<div style="display:flex;gap:18px;flex-wrap:wrap;align-items:center;font-size:14px">'+
          '<span>Identifiant : <b>'+esc(email)+'</b></span><span>Mot de passe : <b class="tnum" id="passShow">'+esc(pass)+'</b></span>'+
          '<button class="btn" id="copyBtn" style="padding:6px 12px">Copier</button>'+
          '<button class="lnk" id="closeRes" style="margin-left:auto">Fermer</button></div>';
      card.classList.remove('hidden');
      $('#copyBtn').onclick = function(){
        try{ navigator.clipboard.writeText('Identifiant : '+email+'\nMot de passe : '+pass); h.toast('Copié ✓'); }catch(err){ h.toast('Copie impossible : sélectionne le texte'); }
      };
      $('#closeRes').onclick = function(){ card.classList.add('hidden'); card.innerHTML = ''; };
    }

    // ----- actions sur les comptes / rôles -----
    root.addEventListener('change', async function(e){
      var s = e.target.closest('[data-role]'); if(!s) return;
      s.disabled = true;
      var r = await call('modifier', { user_id:s.dataset.role, role_id:parseInt(s.value, 10) });
      if(r.error){ h.toast(r.error); } else { h.toast('Rôle mis à jour ✓'); }
      load();
    });
    root.addEventListener('click', async function(e){
      var a = e.target.closest('[data-actif]');
      if(a){
        var u = comptes.filter(function(x){ return x.id === a.dataset.actif; })[0], on = a.dataset.val === '1';
        if(!confirm((on ? 'Réactiver' : 'Désactiver')+' le compte de '+u.nom+' ?'+(on ? '' : '\nIl ne pourra plus se connecter.'))) return;
        var r = await call('activer', { user_id:u.id, actif:on });
        h.toast(r.error || ('Compte '+(on ? 'réactivé' : 'désactivé')+' ✓')); load(); return;
      }
      var m = e.target.closest('[data-mdp]');
      if(m){
        var v = comptes.filter(function(x){ return x.id === m.dataset.mdp; })[0], pass = motDePasse();
        if(!confirm('Réinitialiser le mot de passe de '+v.nom+' ?\nUn nouveau mot de passe sera généré et affiché.')) return;
        var r2 = await call('mot_de_passe', { user_id:v.id, password:pass });
        if(r2.error){ h.toast(r2.error); return; }
        montrerIdentifiants(v.nom, v.email, pass, 'Nouveau mot de passe');
        return;
      }
      var sv = e.target.closest('[data-save]');
      if(sv){
        var tr = sv.closest('tr'), role = roles.filter(function(x){ return String(x.id) === sv.dataset.save; })[0];
        var perms = Object.assign({}, role.permissions || {});
        tr.querySelectorAll('input[data-mod]').forEach(function(cb){ if(cb.checked) perms[cb.dataset.mod] = true; else delete perms[cb.dataset.mod]; });
        sv.disabled = true;
        var res = await store.update('roles', role.id, { permissions:perms });
        sv.disabled = false;
        if(res.error){ h.toast('Erreur : '+res.error.message); return; }
        h.toast('Droits du rôle « '+role.nom+' » enregistrés ✓'); load();
      }
    });

    $('#seg').addEventListener('click', function(e){
      var b = e.target.closest('button[data-v]'); if(!b) return;
      vue = b.dataset.v; $('#fCard').classList.add('hidden'); load();
    });
    $('#newBtn').addEventListener('click', ouvrirForm);
    $('#refreshBtn').addEventListener('click', load);
    await load();
  }
});
