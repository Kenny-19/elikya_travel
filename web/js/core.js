/* core.js — registre des modules + helpers partagés */
window.Elikya = (function(){
  var modules = [];
  var helpers = {
    money: function(n, code){
      return Number(n||0).toLocaleString('fr-FR') + ' ' + (code==='CDF' ? 'FC' : '$');
    },
    // suffixe de message quand une saisie a été gardée en local (hors ligne)
    saved: function(res){ return res && res.offline ? ' · hors ligne, sera synchronisé' : ' ✓'; },
    num: function(n){ return Number(n||0).toLocaleString('fr-FR'); },
    pill: function(label, kind){ return '<span class="pill '+(kind||'neutral')+'">'+label+'</span>'; },
    toast: function(m){
      var t = document.getElementById('toast');
      if(!t) return;
      t.textContent = m; t.classList.add('show');
      setTimeout(function(){ t.classList.remove('show'); }, 2200);
    },
    // squelette de chargement réutilisable
    loadingRow: function(cols){
      return '<tr><td colspan="'+cols+'" style="padding:26px;text-align:center;color:var(--muted)"><span class="spin"></span> Chargement…</td></tr>';
    },
    // placeholder pour un module pas encore implémenté
    placeholder: function(label, desc){
      return '<div class="phead"><div><div class="eyebrow">Module</div><h1 class="pf">'+label+'</h1></div></div>'+
        '<div class="card"><div class="placeholder"><div class="ic">◴</div>'+
        '<b style="font-size:16px;color:var(--ink)">Module « '+label+' » à venir</b>'+
        '<p style="max-width:40ch;margin-top:6px">'+(desc||'')+'</p>'+
        '<p style="margin-top:4px;font-size:12px">À implémenter en suivant <code>web/js/modules/voyage.js</code>.</p>'+
        '</div></div>';
    }
  };
  return {
    db: null,          // client Supabase (défini par supabaseClient.js)
    user: null,        // utilisateur connecté
    modules: modules,
    registerModule: function(m){ modules.push(m); },
    getModule: function(id){ return modules.filter(function(x){return x.id===id;})[0]; },
    h: helpers
  };
})();
