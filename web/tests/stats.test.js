// Tests des calculs du tableau de bord / rapports.  Lancer :  node --test web/tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('../js/stats.js');

const NOW = new Date(2026, 10, 22, 15, 0); // 22 nov. 2026, heure locale
const devises = [{ id: 1, code: 'USD', taux: 1 }, { id: 2, code: 'CDF', taux: 2800 }];
const iso = (y, m, d, h = 10) => new Date(y, m - 1, d, h).toISOString();

const src = {
  devises,
  dossiers: [
    { id: 'd1', ref: 'ELK-1', client_id: 'c1', agent_id: 'u1', montant: 520, devise_id: 1, statut: 'confirme', cree_le: iso(2026, 11, 22) },
    { id: 'd2', ref: 'ELK-2', client_id: 'c1', agent_id: 'u1', montant: 280000, devise_id: 2, statut: 'paye', cree_le: iso(2026, 11, 21) },
    { id: 'd3', ref: 'ELK-3', client_id: 'c2', agent_id: 'u2', montant: 9999, devise_id: 1, statut: 'annule', cree_le: iso(2026, 11, 22) },
    { id: 'd4', ref: 'ELK-4', client_id: 'c2', agent_id: 'u2', montant: 300, devise_id: 1, statut: 'devis', cree_le: iso(2026, 11, 14) },
  ],
  commandes: [
    { id: 'k1', ref: 'CMD-1', client_id: 'c2', statut: 'a_livrer', total: 300, cree_le: iso(2026, 11, 22) },
    { id: 'k2', ref: 'CMD-2', client_id: 'c2', statut: 'annulee', total: 999, cree_le: iso(2026, 11, 22) },
  ],
  momo_transactions: [
    { id: 't1', statut: 'reussi', montant: 120, frais: 1.2, agent_id: 'u3', cree_le: iso(2026, 11, 22) },
    { id: 't2', statut: 'en_attente', montant: 150, frais: 1.5, agent_id: 'u3', cree_le: iso(2026, 11, 22) },
    { id: 't3', statut: 'echec', montant: 50, frais: 0, agent_id: 'u3', cree_le: iso(2026, 11, 20) },
  ],
  caisse_sessions: [
    { id: 's1', jour: '2026-11-22', solde_ouverture: 545, statut: 'ouverte' },
    { id: 's0', jour: '2026-11-20', solde_ouverture: 100, statut: 'ouverte', users: { nom: 'Agent B' } },
    { id: 's9', jour: '2026-11-19', solde_ouverture: 100, statut: 'cloturee', solde_cloture: 90 },
  ],
  mouvements_caisse: [
    { session_id: 's1', sens: 'entree', montant: 520, devise_id: 1, agent_id: 'u1', cree_le: iso(2026, 11, 22) },
    { session_id: 's1', sens: 'sortie', montant: 112000, devise_id: 2, agent_id: 'u1', cree_le: iso(2026, 11, 22) },
  ],
  produits: [
    { ref: 'A', designation: 'Tuyau', stock: 240, seuil_alerte: 20 },
    { ref: 'B', designation: 'Casque', stock: 8, seuil_alerte: 10 },
    { ref: 'C', designation: 'Ruban', stock: 0, seuil_alerte: 10 },
    { ref: 'D', designation: 'Ancien', stock: 0, seuil_alerte: 10, actif: false },
  ],
};

test('périodes : jour, 7 jours, mois en cours, période précédente', () => {
  const j = S.periodRange('jour', NOW);
  assert.deepEqual(j.days, ['2026-11-22']);
  assert.equal(S.dayKey(j.prevFrom), '2026-11-21');
  const s = S.periodRange('semaine', NOW);
  assert.equal(s.days.length, 7);
  assert.equal(s.days[0], '2026-11-16');
  assert.equal(S.dayKey(s.prevFrom), '2026-11-09');
  assert.equal(S.dayKey(s.prevTo), '2026-11-15');
  const m = S.periodRange('mtd', NOW);
  assert.equal(m.days[0], '2026-11-01');
  assert.equal(m.length, 22);
  assert.equal(S.monthRange('2026-11', NOW).days.length, 22, 'mois en cours coupé à aujourd hui');
  assert.equal(S.monthRange('2026-02', NOW).days.length, 28);
});

test('journal + totaux : annulés exclus, CDF converti, seules les transactions réussies', () => {
  const e = S.journal(src);
  const t = S.totals(e, new Date(2026, 10, 21), new Date(2026, 10, 22));
  assert.equal(t['Voyage'], 620); // 520 + 280 000 / 2800
  assert.equal(t['Fourniture'], 300);
  assert.equal(t['Mobile Money'], 120);
  assert.equal(t.frais, 1.2);
  assert.equal(t.nb['Voyage'], 2);
  const jour = S.totals(e, new Date(2026, 10, 22), new Date(2026, 10, 22));
  assert.equal(jour['Voyage'], 520);
});

test('variation en %', () => {
  assert.equal(S.delta(150, 100), 50);
  assert.equal(S.delta(50, 100), -50);
  assert.equal(S.delta(10, 0), null);
  assert.equal(S.delta(0, 0), 0);
});

test('série journalière par module', () => {
  const rows = S.daily(S.journal(src), ['2026-11-21', '2026-11-22']);
  assert.deepEqual(rows[0], { jour: '2026-11-21', Voyage: 100, Location: 0, Fourniture: 0, 'Mobile Money': 0 });
  assert.deepEqual(rows[1], { jour: '2026-11-22', Voyage: 520, Location: 0, Fourniture: 300, 'Mobile Money': 120 });
});

test('caisse : solde théorique des sessions ouvertes et écart de clôture', () => {
  const c = S.caisse(src);
  assert.equal(c.ouvertes.find((o) => o.session.id === 's1').theorique, 545 + 520 - 40);
  assert.equal(c.soldeOuvert, 1025 + 100);
  assert.equal(c.cloturees[0].ecart, -10);
  assert.deepEqual(c.parJour['2026-11-22'], { entrees: 520, sorties: 40 });
});

test('alertes triées par gravité', () => {
  const a = S.alertes(src, NOW);
  assert.equal(a[0].niveau, 'crit');
  const textes = a.map((x) => x.texte);
  assert.ok(textes.some((t) => t.startsWith('Rupture : C')));
  assert.ok(!textes.some((t) => t.includes('Ancien')), 'produit inactif ignoré');
  assert.ok(textes.some((t) => t.startsWith('Stock bas : B')));
  assert.ok(textes.includes('1 transaction(s) en attente de confirmation'));
  assert.ok(textes.some((t) => t.includes('20/11/2026 non clôturée (Agent B)')));
  assert.ok(!textes.some((t) => t.includes('22/11/2026 non clôturée')), 'la session du jour n est pas en retard');
  assert.ok(textes.some((t) => t.startsWith('Manquant de 10')));
  assert.ok(textes.includes('1 commande(s) à livrer'));
  assert.ok(textes.includes('1 devis à relancer'));
  const rank = { crit: 0, warn: 1, info: 2 };
  for (let i = 1; i < a.length; i++) assert.ok(rank[a[i - 1].niveau] <= rank[a[i].niveau]);
});

test('par agent et meilleurs clients', () => {
  const e = S.journal(src);
  const ag = S.parAgent(e, src.mouvements_caisse, [{ id: 'u1', nom: 'Vente' }, { id: 'u3', nom: 'MoMo' }]);
  const u1 = ag.find((r) => r.agent_id === 'u1');
  assert.equal(u1.nom, 'Vente');
  assert.equal(u1['Voyage'], 620);
  assert.equal(u1.mouvements, 2);
  assert.equal(ag.find((r) => r.agent_id === 'u3').nbMomo, 1);
  const top = S.topClients(e, [{ id: 'c1', nom: 'Patrick' }, { id: 'c2', nom: 'Kamoa' }]);
  assert.deepEqual(top.map((c) => [c.nom, c.ca]), [['Patrick', 620], ['Kamoa', 600]]);
});

test('CSV Excel FR', () => {
  const csv = S.toCsv([{ a: 'Kamoa; SARL', b: 1234.5 }, { a: 'Dit "X"', b: null }], [{ key: 'a', label: 'Client' }, { key: 'b', label: 'CA' }]);
  assert.equal(csv, 'Client;CA\r\n"Kamoa; SARL";1234,5\r\n"Dit ""X""";');
});

test('graduations rondes', () => {
  assert.deepEqual(S.niceTicks(940).ticks, [0, 250, 500, 750, 1000]);
  assert.deepEqual(S.niceTicks(0).ticks, [0, 1]);
  assert.equal(S.niceTicks(12).max, 15);
});

test('réservations : seules les commandes « à livrer » comptent', () => {
  const r = S.reservations(
    [{ id: 'k1', statut: 'a_livrer' }, { id: 'k2', statut: 'livree' }],
    [{ commande_id: 'k1', produit_id: 'p1', quantite: 25 }, { commande_id: 'k1', produit_id: 'p1', quantite: 5 }, { commande_id: 'k2', produit_id: 'p2', quantite: 50 }],
  );
  assert.deepEqual(r, { p1: 30 });
});

test('CA par client sur tout l historique : CDF converti, annulés exclus', () => {
  const s = S.statsClients(src.dossiers, src.commandes, devises);
  assert.deepEqual(s.c1, { dossiers: 2, commandes: 0, ca: 620 });
  assert.deepEqual(s.c2, { dossiers: 1, commandes: 1, ca: 600 }); // devis 300 + commande 300 ; annulés exclus
});

test('location : jours, montant, conflits, état (mêmes règles que l’app)', () => {
  const v = { id: 'v1', tarif_jour: 80, tarif_chauffeur_jour: 25, statut: 'disponible' };
  const locs = [
    { id: 'l1', vehicule_id: 'v1', date_debut: '2026-11-20', date_fin: '2026-11-24', statut: 'en_cours' },
    { id: 'l2', vehicule_id: 'v1', date_debut: '2026-12-01', date_fin: '2026-12-03', statut: 'reservee' },
    { id: 'l3', vehicule_id: 'v1', date_debut: '2026-11-26', date_fin: '2026-11-28', statut: 'annulee' },
  ];
  assert.equal(S.locJours('2026-11-01', '2026-11-03'), 3);
  assert.equal(S.locJours('2026-12-30', '2027-01-02'), 4);
  assert.equal(S.locMontant(v, '2026-11-01', '2026-11-03', true), 315);
  assert.equal(S.locConflit(locs, 'v1', '2026-11-24', '2026-11-25').id, 'l1');
  assert.equal(S.locConflit(locs, 'v1', '2026-11-25', '2026-11-30'), null);
  assert.equal(S.locConflit(locs, 'v1', '2026-12-01', '2026-12-02', 'l2'), null);
  assert.equal(S.locEtat(v, locs, '2026-11-22').libelle, 'Loué jusqu’au 24/11');
  assert.equal(S.locEtat(v, locs, '2026-11-26').code, 'retard');
  const rendu = locs.map((l) => (l.id === 'l1' ? { ...l, statut: 'terminee' } : l));
  assert.equal(S.locEtat(v, rendu, '2026-11-26').libelle, 'Libre · réservé dès le 01/12');
  assert.equal(S.locEtat({ ...v, statut: 'entretien' }, locs, '2026-11-22').code, 'entretien');
  assert.equal(S.locEtat(v, rendu, '2026-12-01').code, 'a_remettre', 'réservé, départ aujourd’hui');
});

test('location dans le journal : annulées exclues, CDF converti, client compté', () => {
  const e = S.journal({
    devises,
    locations: [
      { id: 'L1', ref: 'LOC-1', client_id: 'c9', agent_id: 'u1', montant: 315, devise_id: 1, statut: 'en_cours', cree_le: iso(2026, 11, 22) },
      { id: 'L2', ref: 'LOC-2', client_id: 'c9', agent_id: 'u1', montant: 280000, devise_id: 2, statut: 'reservee', cree_le: iso(2026, 11, 22) },
      { id: 'L3', ref: 'LOC-3', client_id: 'c9', agent_id: 'u1', montant: 999, devise_id: 1, statut: 'annulee', cree_le: iso(2026, 11, 22) },
    ],
  });
  const t = S.totals(e, new Date(2026, 10, 22), new Date(2026, 10, 22));
  assert.equal(t['Location'], 415);
  assert.equal(t.nb['Location'], 2);
  assert.deepEqual(S.topClients(e, [{ id: 'c9', nom: 'Kamoa' }]).map((c) => c.ca), [415]);
  assert.deepEqual(S.MODULES, ['Voyage', 'Location', 'Fourniture', 'Mobile Money']);
});

test('alerte : véhicule non rendu', () => {
  const a = S.alertes({ locations: [
    { ref: 'LOC-7', statut: 'en_cours', date_debut: '2026-11-18', date_fin: '2026-11-20' },
    { ref: 'LOC-8', statut: 'en_cours', date_debut: '2026-11-20', date_fin: '2026-11-25' },
  ] }, NOW);
  assert.deepEqual(a.map((x) => [x.niveau, x.texte]), [['crit', 'Véhicule non rendu : LOC-7 (retour prévu le 20/11/2026)']]);
});

test('voyage : paiements (mêmes règles que l’app)', () => {
  const d = { id: 'd1', montant: 500, devise_id: 1, statut: 'confirme' };
  assert.equal(S.voyPaiement(d, [], devises).code, 'non_paye');
  const e = S.voyPaiement(d, [{ montant: 200, devise_id: 1 }, { montant: 280000, devise_id: 2 }], devises);
  assert.deepEqual([e.code, e.paye, e.reste, e.libelle], ['acompte', 300, 200, 'Acompte']);
  assert.equal(S.voyPaiement(d, [{ montant: 500, devise_id: 1 }], devises).code, 'solde');
  assert.equal(S.voyPaiement({ ...d, statut: 'paye' }, [], devises).code, 'solde', 'ancien dossier « payé »');
  const cdf = S.voyPaiement({ montant: 1400000, devise_id: 2, statut: 'confirme' }, [{ montant: 250, devise_id: 1 }], devises);
  assert.deepEqual([cdf.paye, cdf.reste], [700000, 700000]);
  assert.equal(S.voyAvancement({ statut: 'en_cours' }), 'confirme');
  assert.equal(S.voyPaiementsDe([{ source_type: 'dossier', source_id: 'd1' }, { source_type: 'commande', source_id: 'd1' }], 'd1').length, 1);
});

test('alerte : départ proche pas soldé', () => {
  const a = S.alertes({
    devises,
    departs: [
      { id: 'd1', ref: 'ELK-1', statut: 'confirme', date_depart: '2026-11-24', montant: 500, devise_id: 1, clients: { nom: 'Patrick' } },
      { id: 'd2', ref: 'ELK-2', statut: 'confirme', date_depart: '2026-11-24', montant: 100, devise_id: 1 },
      { id: 'd3', ref: 'ELK-3', statut: 'annule', date_depart: '2026-11-24', montant: 100, devise_id: 1 },
    ],
    paiements: [{ source_type: 'dossier', source_id: 'd1', montant: 200, devise_id: 1 }, { source_type: 'dossier', source_id: 'd2', montant: 100, devise_id: 1 }],
  }, NOW);
  assert.deepEqual(a.map((x) => x.texte), ['Départ le 24/11/2026 pas soldé : ELK-1 (Patrick) — reste 300 $']);
});
