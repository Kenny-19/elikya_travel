/* supabaseClient.js — initialise le client Supabase depuis web/config.js */
(function(){
  if(!window.ELIKYA_CONFIG){
    console.error("config.js manquant : copie web/config.example.js en web/config.js");
    window.ELIKYA_CONFIG = { url:"", anonKey:"" };
  }
  Elikya.configOk = !!(ELIKYA_CONFIG.url && ELIKYA_CONFIG.anonKey && ELIKYA_CONFIG.anonKey.indexOf("COLLE_TA")!==0);
  if(Elikya.configOk && window.supabase){
    Elikya.db = window.supabase.createClient(ELIKYA_CONFIG.url, ELIKYA_CONFIG.anonKey);
  }
})();
