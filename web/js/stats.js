/* stats.js — calculs du tableau de bord et des rapports (fonctions PURES, sans accès réseau).
   Tout est ramené en USD (CDF ÷ taux de la table devises). Testé par web/tests/stats.test.js (node).
   Règles :
     - Voyage      = dossiers non annulés (montant à la date de création du dossier)
     - Fourniture  = commandes non annulées (total)
     - Mobile Money= transactions réussies (volume) ; frais = commissions
     - Caisse      = mouvements entrées / sorties ; solde théorique des sessions ouvertes */
(function(root){
  var MODULES = ['Voyage','Location','Fourniture','Mobile Money'];

  function num(v){ var n = Number(v); return isFinite(n) ? n : 0; }
  function round2(n){ return Math.round(n*100)/100; }

  function tauxMap(devises){
    var m = {};
    (devises||[]).forEach(function(d){ m[String(d.id)] = num(d.taux) || 1; });
    return m;
  }
  function toUsd(montant, deviseId, taux){ return num(montant) / ((taux && taux[String(deviseId)]) || 1); }

  function pad(n){ return (n<10?'0':'')+n; }
  /** Jour LOCAL 'AAAA-MM-JJ' d'une date, d'un horodatage ISO ou d'une date 'AAAA-MM-JJ'. */
  function dayKey(v){
    if(v == null) return null;
    if(typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
    var d = v instanceof Date ? v : new Date(v);
    if(isNaN(d)) return null;
    return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate());
  }
  /** 'AAAA-MM-JJ' → 'JJ/MM/AAAA' (affichage). */
  function frDate(k){ return k && /^\d{4}-\d{2}-\d{2}$/.test(k) ? k.slice(8)+'/'+k.slice(5,7)+'/'+k.slice(0,4) : k; }
  function addDays(d, n){ var x = new Date(d.getFullYear(), d.getMonth(), d.getDate()); x.setDate(x.getDate()+n); return x; }
  function daysBetween(from, to){ // inclus
    var out = [], d = new Date(from.getFullYear(), from.getMonth(), from.getDate());
    while(d <= to){ out.push(dayKey(d)); d = addDays(d, 1); }
    return out;
  }

  /** Période + période précédente de même longueur.
      preset : 'jour' | 'semaine' (7 j) | 'mois' (30 j) | 'mtd' (depuis le 1er du mois). */
  function periodRange(preset, now){
    now = now || new Date();
    var to = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var from;
    if(preset === 'semaine') from = addDays(to, -6);
    else if(preset === 'mois') from = addDays(to, -29);
    else if(preset === 'mtd') from = new Date(to.getFullYear(), to.getMonth(), 1);
    else from = to;
    var len = daysBetween(from, to).length;
    var prevTo = addDays(from, -1), prevFrom = addDays(from, -len);
    return { from:from, to:to, days:daysBetween(from, to), prevFrom:prevFrom, prevTo:prevTo, length:len };
  }

  /** Bornes d'un mois 'AAAA-MM' (jusqu'à aujourd'hui si mois en cours). */
  function monthRange(ym, now){
    now = now || new Date();
    var p = ym.split('-'), y = +p[0], m = +p[1]-1;
    var from = new Date(y, m, 1), end = new Date(y, m+1, 0);
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var to = end > today ? today : end;
    return { from:from, to:to, days: to < from ? [] : daysBetween(from, to) };
  }

  /** Journal unifié des ventes / volumes : [{jour, module, montant, frais, client_id, agent_id, ref}] */
  function journal(src){
    var taux = tauxMap(src.devises), out = [];
    (src.dossiers||[]).forEach(function(d){
      if(d.statut === 'annule') return;
      out.push({ jour:dayKey(d.cree_le), module:'Voyage', montant:toUsd(d.montant, d.devise_id, taux), frais:0,
                 client_id:d.client_id, agent_id:d.agent_id, ref:d.ref });
    });
    (src.commandes||[]).forEach(function(c){
      if(c.statut === 'annulee') return;
      out.push({ jour:dayKey(c.cree_le), module:'Fourniture', montant:num(c.total), frais:0,
                 client_id:c.client_id, agent_id:null, ref:c.ref });
    });
    (src.locations||[]).forEach(function(l){
      if(l.statut === 'annulee') return;
      out.push({ jour:dayKey(l.cree_le), module:'Location', montant:toUsd(l.montant, l.devise_id, taux), frais:0,
                 client_id:l.client_id, agent_id:l.agent_id, ref:l.ref });
    });
    (src.momo_transactions||[]).forEach(function(t){
      if(t.statut !== 'reussi') return;
      out.push({ jour:dayKey(t.cree_le), module:'Mobile Money', montant:num(t.montant), frais:num(t.frais),
                 client_id:null, agent_id:t.agent_id, ref:null });
    });
    return out;
  }

  function inRange(jour, from, to){ var k = jour; return k >= dayKey(from) && k <= dayKey(to); }

  /** Totaux par module sur [from, to] : {Voyage, Fourniture, 'Mobile Money', frais, nb:{...}} */
  function totals(entries, from, to){
    var t = { frais:0, nb:{} };
    MODULES.forEach(function(m){ t[m] = 0; t.nb[m] = 0; });
    entries.forEach(function(e){
      if(!e.jour || !inRange(e.jour, from, to)) return;
      t[e.module] += e.montant; t.nb[e.module]++; t.frais += e.frais;
    });
    MODULES.forEach(function(m){ t[m] = round2(t[m]); });
    t.frais = round2(t.frais);
    return t;
  }

  /** Variation en % (null si pas de base de comparaison). */
  function delta(cur, prev){ return prev ? Math.round((cur - prev) / prev * 100) : (cur ? null : 0); }

  /** Série journalière par module, pour les colonnes empilées : [{jour, Voyage, Fourniture, 'Mobile Money'}] */
  function daily(entries, days){
    var idx = {};
    var rows = days.map(function(k){ var r = { jour:k }; MODULES.forEach(function(m){ r[m] = 0; }); idx[k] = r; return r; });
    entries.forEach(function(e){ var r = idx[e.jour]; if(r) r[e.module] += e.montant; });
    rows.forEach(function(r){ MODULES.forEach(function(m){ r[m] = round2(r[m]); }); });
    return rows;
  }

  /** Caisse : entrées / sorties en USD par jour + solde théorique des sessions ouvertes. */
  function caisse(src){
    var taux = tauxMap(src.devises), parSession = {}, parJour = {};
    (src.mouvements_caisse||[]).forEach(function(m){
      var v = toUsd(m.montant, m.devise_id, taux), s = parSession[m.session_id] = parSession[m.session_id] || { in:0, out:0 };
      var j = parJour[dayKey(m.cree_le)] = parJour[dayKey(m.cree_le)] || { entrees:0, sorties:0 };
      if(m.sens === 'entree'){ s.in += v; j.entrees += v; } else { s.out += v; j.sorties += v; }
    });
    var ouvertes = (src.caisse_sessions||[]).filter(function(s){ return s.statut === 'ouverte'; }).map(function(s){
      var x = parSession[s.id] || { in:0, out:0 };
      return { session:s, theorique: round2(num(s.solde_ouverture) + x.in - x.out) };
    });
    var cloturees = (src.caisse_sessions||[]).filter(function(s){ return s.statut === 'cloturee' && s.solde_cloture != null; }).map(function(s){
      var x = parSession[s.id] || { in:0, out:0 }, theo = num(s.solde_ouverture) + x.in - x.out;
      return { session:s, theorique: round2(theo), ecart: round2(num(s.solde_cloture) - theo) };
    });
    return { parJour:parJour, ouvertes:ouvertes, cloturees:cloturees,
             soldeOuvert: round2(ouvertes.reduce(function(a, o){ return a + o.theorique; }, 0)) };
  }

  /** Alertes à traiter : [{niveau:'crit'|'warn'|'info', module, texte}] triées par gravité. */
  function alertes(src, now){
    now = now || new Date();
    var today = dayKey(now), il30j = dayKey(addDays(now, -30)), out = [];
    (src.produits||[]).forEach(function(p){
      if(p.actif === false) return;
      if(num(p.stock) <= 0) out.push({ niveau:'crit', module:'Fourniture', texte:'Rupture : '+p.ref+' · '+p.designation });
      else if(num(p.stock) <= num(p.seuil_alerte)) out.push({ niveau:'warn', module:'Fourniture',
        texte:'Stock bas : '+p.ref+' · '+p.designation+' ('+num(p.stock)+' / seuil '+num(p.seuil_alerte)+')' });
    });
    var att = (src.momo_transactions||[]).filter(function(t){ return t.statut === 'en_attente'; }).length;
    var ko = (src.momo_transactions||[]).filter(function(t){ return t.statut === 'echec'; }).length;
    if(att) out.push({ niveau:'warn', module:'Mobile Money', texte: att+' transaction(s) en attente de confirmation' });
    if(ko) out.push({ niveau:'info', module:'Mobile Money', texte: ko+' transaction(s) en échec sur la période' });
    (src.caisse_sessions||[]).forEach(function(s){
      if(s.statut === 'ouverte' && s.jour < today)
        out.push({ niveau:'warn', module:'Caisse', texte:'Session du '+frDate(s.jour)+' non clôturée'+(s.users && s.users.nom ? ' ('+s.users.nom+')' : '') });
    });
    caisse(src).cloturees.forEach(function(c){
      if(Math.abs(c.ecart) >= 0.01 && c.session.jour >= il30j)
        out.push({ niveau: c.ecart < 0 ? 'crit' : 'warn', module:'Caisse',
          texte:(c.ecart < 0 ? 'Manquant de ' : 'Excédent de ')+Math.abs(c.ecart).toLocaleString('fr-FR')+' $ à la clôture du '+frDate(c.session.jour) });
    });
    (src.locations||[]).forEach(function(l){
      if(locEnRetard(l, today)) out.push({ niveau:'crit', module:'Location',
        texte:'Véhicule non rendu : '+(l.ref||'location')+' (retour prévu le '+frDate(l.date_fin)+')' });
    });
    var aLivrer = (src.commandes||[]).filter(function(c){ return c.statut === 'a_livrer'; }).length;
    if(aLivrer) out.push({ niveau:'info', module:'Fourniture', texte: aLivrer+' commande(s) à livrer' });
    var devis = (src.dossiers||[]).filter(function(d){ return d.statut === 'devis'; }).length;
    if(devis) out.push({ niveau:'info', module:'Voyage', texte: devis+' devis à relancer' });
    // départs dans les 3 jours pas encore soldés (src.departs + src.paiements)
    (src.departs||[]).forEach(function(d){
      var a = voyAvancement(d); if(a !== 'devis' && a !== 'confirme') return;
      var p = voyPaiement(d, voyPaiementsDe(src.paiements, d.id), src.devises);
      if(p.reste > 0) out.push({ niveau:'crit', module:'Voyage',
        texte:'Départ le '+frDate(d.date_depart)+' pas soldé : '+(d.ref||'dossier')+(d.clients && d.clients.nom ? ' ('+d.clients.nom+')' : '')+' — reste '+p.reste.toLocaleString('fr-FR')+(((src.devises||[]).filter(function(x){ return String(x.id) === String(d.devise_id); })[0] || {}).code === 'CDF' ? ' FC' : ' $') });
    });
    var rank = { crit:0, warn:1, info:2 };
    return out.sort(function(a, b){ return rank[a.niveau] - rank[b.niveau]; });
  }

  /** Synthèse par agent : [{agent_id, nom, Voyage, nbVoyage, 'Mobile Money', nbMomo, mouvements}] */
  function parAgent(entries, mouvements, users){
    var noms = {}; (users||[]).forEach(function(u){ noms[u.id] = u.nom; });
    var m = {};
    function row(id){ var k = id || '_'; return m[k] = m[k] || { agent_id:id||null, nom: id ? (noms[id] || 'Agent inconnu') : 'Sans agent',
      'Voyage':0, nbVoyage:0, 'Mobile Money':0, nbMomo:0, mouvements:0 }; }
    entries.forEach(function(e){
      if(e.module === 'Voyage'){ var r = row(e.agent_id); r['Voyage'] += e.montant; r.nbVoyage++; }
      else if(e.module === 'Mobile Money'){ var q = row(e.agent_id); q['Mobile Money'] += e.montant; q.nbMomo++; }
    });
    (mouvements||[]).forEach(function(x){ row(x.agent_id).mouvements++; });
    return Object.keys(m).map(function(k){ var r = m[k]; r['Voyage'] = round2(r['Voyage']); r['Mobile Money'] = round2(r['Mobile Money']); return r; })
      .sort(function(a, b){ return (b['Voyage'] + b['Mobile Money']) - (a['Voyage'] + a['Mobile Money']); });
  }

  /** Meilleurs clients (voyage + fourniture) : [{client_id, nom, ca, nb}] */
  function topClients(entries, clients, n){
    var noms = {}; (clients||[]).forEach(function(c){ noms[c.id] = c.nom; });
    var m = {};
    entries.forEach(function(e){
      if(!e.client_id) return;
      var r = m[e.client_id] = m[e.client_id] || { client_id:e.client_id, nom: noms[e.client_id] || 'Client inconnu', ca:0, nb:0 };
      r.ca += e.montant; r.nb++;
    });
    return Object.keys(m).map(function(k){ m[k].ca = round2(m[k].ca); return m[k]; })
      .sort(function(a, b){ return b.ca - a.ca; }).slice(0, n || 10);
  }

  /** Quantités réservées par produit = lignes des commandes « à livrer » : {produit_id: qté} */
  function reservations(commandes, lignes){
    var aLivrer = {};
    (commandes||[]).forEach(function(c){ if(c.statut === 'a_livrer') aLivrer[c.id] = true; });
    var out = {};
    (lignes||[]).forEach(function(l){ if(aLivrer[l.commande_id]) out[l.produit_id] = (out[l.produit_id]||0) + num(l.quantite); });
    return out;
  }

  /** Par client (tout l'historique, hors annulés, USD) : {client_id: {dossiers, commandes, ca}} */
  function statsClients(dossiers, commandes, devises){
    var taux = tauxMap(devises), out = {};
    function row(id){ return out[id] = out[id] || { dossiers:0, commandes:0, ca:0 }; }
    (dossiers||[]).forEach(function(d){ if(d.statut === 'annule') return; var r = row(d.client_id); r.dossiers++; r.ca += toUsd(d.montant, d.devise_id, taux); });
    (commandes||[]).forEach(function(c){ if(c.statut === 'annulee') return; var r = row(c.client_id); r.commandes++; r.ca += num(c.total); });
    Object.keys(out).forEach(function(k){ out[k].ca = round2(out[k].ca); });
    return out;
  }

  // ----- Voyage : avancement et paiements (mêmes règles que agents/lib/data/voyage_logic.dart) -----
  /** Avancement du dossier, indépendant du paiement ('paye' / 'en_cours' anciens → 'confirme'). */
  function voyAvancement(d){ return d.statut === 'devis' || d.statut === 'termine' || d.statut === 'annule' ? d.statut : 'confirme'; }
  /** Encaissements d'un dossier (ou d'une location : type 'location'). */
  function voyPaiementsDe(paiements, id, type){ return (paiements||[]).filter(function(p){ return p.source_type === (type||'dossier') && String(p.source_id) === String(id); }); }
  /** {code, paye, reste, libelle} — encaissements convertis dans la devise du dossier. */
  function voyPaiement(d, pDossier, devises){
    var total = num(d.montant), taux = tauxMap(devises);
    var lib = { sans_montant:'Sans montant', non_paye:'Non payé', acompte:'Acompte', solde:'Soldé', trop_percu:'Trop perçu' };
    function r(code, paye, reste){ return { code:code, paye:paye, reste:reste, libelle:lib[code] }; }
    if(total <= 0) return r('sans_montant', 0, 0);
    if(!(pDossier||[]).length && d.statut === 'paye') return r('solde', total, 0);
    var tD = taux[String(d.devise_id)] || 1;
    var paye = round2((pDossier||[]).reduce(function(s, p){ return s + num(p.montant) / (taux[String(p.devise_id)] || 1) * tD; }, 0));
    var reste = round2(total - paye);
    if(paye <= 0.004) return r('non_paye', 0, total);
    if(reste > 0.004) return r('acompte', paye, reste);
    if(reste < -0.004) return r('trop_percu', paye, 0);
    return r('solde', paye, 0);
  }

  // ----- Location de véhicules (mêmes règles que agents/lib/data/location_logic.dart) -----
  var LOC_ACTIFS = { reservee:true, en_cours:true };
  /** Jours facturés : départ et retour inclus (du 1er au 3 = 3 jours), minimum 1. */
  function locJours(debut, fin){
    var a = Date.UTC(+debut.slice(0,4), +debut.slice(5,7)-1, +debut.slice(8,10));
    var b = Date.UTC(+fin.slice(0,4), +fin.slice(5,7)-1, +fin.slice(8,10));
    return Math.max(1, Math.round((b - a) / 864e5) + 1);
  }
  /** Montant proposé (USD) : jours × (tarif véhicule + supplément chauffeur). */
  function locMontant(v, debut, fin, avecChauffeur){
    return locJours(debut, fin) * (num(v.tarif_jour) + (avecChauffeur ? num(v.tarif_chauffeur_jour) : 0));
  }
  /** Première location active du véhicule qui chevauche [debut, fin] (bornes incluses), ou null. */
  function locConflit(locations, vehiculeId, debut, fin, saufId){
    return (locations||[]).filter(function(l){
      return String(l.vehicule_id) === String(vehiculeId) && LOC_ACTIFS[l.statut] && (saufId == null || String(l.id) !== String(saufId))
        && debut <= l.date_fin && fin >= l.date_debut;
    })[0] || null;
  }
  function locEnRetard(l, today){ return l.statut === 'en_cours' && l.date_fin < today; }
  /** État du véhicule à une date : {code, libelle, location} */
  function locEtat(v, locations, today){
    if(v.statut === 'entretien') return { code:'entretien', libelle:'En entretien' };
    if(v.statut === 'hors_service') return { code:'hors_service', libelle:'Hors service' };
    var court = function(k){ return k.slice(8)+'/'+k.slice(5,7); };
    var actives = (locations||[]).filter(function(l){ return String(l.vehicule_id) === String(v.id) && LOC_ACTIFS[l.statut]; })
      .sort(function(a, b){ return a.date_debut < b.date_debut ? -1 : 1; });
    for(var i = 0; i < actives.length; i++){
      var l = actives[i];
      if(locEnRetard(l, today)) return { code:'retard', libelle:'Retour en retard (prévu le '+court(l.date_fin)+')', location:l };
      if(l.statut === 'en_cours') return { code:'loue', libelle:'Loué jusqu’au '+court(l.date_fin), location:l };
      // réservé et la date de départ est arrivée : le client vient chercher le véhicule
      if(l.date_debut <= today && l.date_fin >= today) return { code:'a_remettre', libelle:'Clés à remettre (réservé)', location:l };
    }
    var next = actives.filter(function(l){ return l.date_debut > today; })[0];
    if(next) return { code:'reserve_plus_tard', libelle:'Libre · réservé dès le '+court(next.date_debut), location:next };
    return { code:'disponible', libelle:'Disponible' };
  }

  /** CSV compatible Excel FR (séparateur « ; », décimales « , »). cols : [{key, label}] */
  function toCsv(rows, cols){
    function cell(v){
      if(v == null) return '';
      if(typeof v === 'number') return String(round2(v)).replace('.', ',');
      var s = String(v);
      return /[";\n]/.test(s) ? '"'+s.replace(/"/g, '""')+'"' : s;
    }
    return [cols.map(function(c){ return cell(c.label); }).join(';')]
      .concat(rows.map(function(r){ return cols.map(function(c){ return cell(r[c.key]); }).join(';'); }))
      .join('\r\n');
  }

  /** Graduations « rondes » d'un axe : {max, step, ticks[]} */
  function niceTicks(max, count){
    count = count || 4;
    if(!(max > 0)) return { max:1, step:1, ticks:[0, 1] };
    var raw = max / count, p = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / p;
    var step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p;
    var top = Math.ceil(max / step) * step, ticks = [];
    for(var v = 0; v <= top + step/2; v += step) ticks.push(round2(v));
    return { max:top, step:step, ticks:ticks };
  }

  var api = { MODULES:MODULES, dayKey:dayKey, periodRange:periodRange, monthRange:monthRange, journal:journal,
    totals:totals, delta:delta, frDate:frDate, daily:daily, caisse:caisse, alertes:alertes, parAgent:parAgent,
    topClients:topClients, reservations:reservations, statsClients:statsClients, toCsv:toCsv,
    voyAvancement:voyAvancement, voyPaiementsDe:voyPaiementsDe, voyPaiement:voyPaiement,
    locJours:locJours, locMontant:locMontant, locConflit:locConflit, locEtat:locEtat, locEnRetard:locEnRetard, niceTicks:niceTicks, toUsd:toUsd, tauxMap:tauxMap };
  if(typeof module !== 'undefined' && module.exports) module.exports = api;
  if(root && root.Elikya) root.Elikya.stats = api;
})(typeof window !== 'undefined' ? window : null);
