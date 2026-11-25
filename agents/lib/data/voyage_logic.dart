// Règles du module Voyage (fonctions pures, testées : test/voyage_logic_test.dart).
// Mêmes règles côté site : web/js/stats.js (voy*).
import 'local_db.dart';

num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
num _r2(num n) => (n * 100).round() / 100;

const typesDossier = {
  'billet': 'Billet d’avion',
  'visa': 'Visa',
  'hotel': 'Hôtel',
  'assurance': 'Assurance',
  'package': 'Package',
};

/// Avancement du dossier (indépendant du paiement). Anciens statuts 'paye' / 'en_cours' → confirmé.
String avancement(JsonRow d) => switch (d['statut']) {
  'devis' => 'devis',
  'termine' => 'termine',
  'annule' => 'annule',
  _ => 'confirme',
};
const libellesAvancement = {'devis': 'Devis', 'confirme': 'Confirmé', 'termine': 'Voyage effectué', 'annule': 'Annulé'};

/// Étapes d'un visa, dans l'ordre.
const etapesVisa = {
  'a_deposer': 'À déposer',
  'depose': 'Déposé',
  'en_traitement': 'En traitement',
  'obtenu': 'Obtenu',
  'refuse': 'Refusé',
};

/// Étape suivante d'un visa (null si terminé : obtenu ou refusé).
String? etapeVisaSuivante(String? e) => switch (e ?? 'a_deposer') {
  'a_deposer' => 'depose',
  'depose' => 'en_traitement',
  _ => null, // en traitement → obtenu OU refusé : c'est l'agent qui choisit
};

class EtatPaiement {
  const EtatPaiement(this.code, this.paye, this.reste);
  final String code; // sans_montant | non_paye | acompte | solde | trop_percu
  final num paye; // encaissé, dans la devise du dossier
  final num reste; // reste à payer (0 si soldé)
  String get libelle => switch (code) {
    'non_paye' => 'Non payé',
    'acompte' => 'Acompte',
    'solde' => 'Soldé',
    'trop_percu' => 'Trop perçu',
    _ => 'Sans montant',
  };
}

/// Encaissements d'un dossier.
List<JsonRow> paiementsDe(List<JsonRow> paiements, Object? dossierId, {String type = 'dossier'}) =>
    paiements.where((p) => p['source_type'] == type && '${p['source_id']}' == '$dossierId').toList();

/// Montant converti d'une devise à l'autre via les taux (USD = 1, CDF = 2800…).
num convertir(num montant, Object? deDevise, Object? versDevise, List<JsonRow> devises) {
  if ('$deDevise' == '$versDevise') return montant;
  num taux(Object? id) {
    final t = _num(devises.where((d) => '${d['id']}' == '$id').firstOrNull?['taux']);
    return t == 0 ? 1 : t;
  }

  return montant / taux(deDevise) * taux(versDevise);
}

/// Où en est le paiement d'un dossier (encaissements convertis dans la devise du dossier).
EtatPaiement etatPaiement(JsonRow d, List<JsonRow> paiementsDuDossier, List<JsonRow> devises) {
  final total = _num(d['montant']);
  if (total <= 0) return const EtatPaiement('sans_montant', 0, 0);
  // ancien dossier marqué « payé » avant le suivi des encaissements
  if (paiementsDuDossier.isEmpty && d['statut'] == 'paye') return EtatPaiement('solde', total, 0);
  final paye = _r2(
    paiementsDuDossier.fold<num>(
      0,
      (s, p) => s + convertir(_num(p['montant']), p['devise_id'], d['devise_id'], devises),
    ),
  );
  final reste = _r2(total - paye);
  if (paye <= 0.004) return EtatPaiement('non_paye', 0, total);
  if (reste > 0.004) return EtatPaiement('acompte', paye, reste);
  if (reste < -0.004) return EtatPaiement('trop_percu', paye, 0);
  return EtatPaiement('solde', paye, 0);
}

/// Nombre de jours avant le départ (négatif si passé), null sans date.
int? joursAvantDepart(JsonRow d, DateTime aujourdhui) {
  final s = d['date_depart'];
  if (s == null || '$s'.isEmpty) return null;
  final dep = DateTime.parse('$s'), t = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  return DateTime.utc(dep.year, dep.month, dep.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
}

/// Départ dans les [jours] prochains alors qu'il reste à payer (dossier actif).
bool departProcheNonSolde(JsonRow d, EtatPaiement p, DateTime aujourdhui, {int jours = 3}) {
  final a = avancement(d);
  if (a == 'annule' || a == 'termine' || p.reste <= 0) return false;
  final n = joursAvantDepart(d, aujourdhui);
  return n != null && n >= 0 && n <= jours;
}
