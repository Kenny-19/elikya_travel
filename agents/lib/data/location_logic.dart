// Règles de la location de véhicules (fonctions pures, testées : test/location_logic_test.dart).
// Mêmes règles côté site : web/js/stats.js (loc*).
// Dates au format 'AAAA-MM-JJ' (comparables comme du texte).
import 'local_db.dart';

/// Locations qui bloquent le véhicule (réservée ou en cours). Terminée / annulée → libèrent.
const statutsActifs = {'reservee', 'en_cours'};

String jourCle(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Nombre de jours facturés : jour de départ et jour de retour inclus (du 1er au 3 = 3 jours).
int joursLocation(String debut, String fin) {
  final a = DateTime.parse(debut), b = DateTime.parse(fin);
  final n = DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;
  return n < 1 ? 1 : n;
}

num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

/// Montant proposé (USD) : jours × (tarif véhicule + supplément chauffeur si avec chauffeur).
num montantConseille(JsonRow vehicule, String debut, String fin, bool avecChauffeur) {
  final parJour = _num(vehicule['tarif_jour']) + (avecChauffeur ? _num(vehicule['tarif_chauffeur_jour']) : 0);
  return joursLocation(debut, fin) * parJour;
}

/// Première location active du véhicule qui chevauche [debut, fin] (bornes incluses), ou null.
JsonRow? conflitLocation(List<JsonRow> locations, Object? vehiculeId, String debut, String fin, {Object? saufId}) {
  for (final l in locations) {
    if ('${l['vehicule_id']}' != '$vehiculeId') continue;
    if (saufId != null && '${l['id']}' == '$saufId') continue;
    if (!statutsActifs.contains(l['statut'])) continue;
    if (debut.compareTo('${l['date_fin']}') <= 0 && fin.compareTo('${l['date_debut']}') >= 0) return l;
  }
  return null;
}

/// État du véhicule à une date.
class EtatVehicule {
  const EtatVehicule(this.code, this.libelle, {this.location});
  final String code; // disponible | loue | retard | a_remettre | reserve_plus_tard | entretien | hors_service
  final String libelle;
  final JsonRow? location; // location concernée (en cours ou prochaine)
}

String jourCourt(String k) => '${k.substring(8)}/${k.substring(5, 7)}';

EtatVehicule etatVehicule(JsonRow v, List<JsonRow> locations, String aujourdhui) {
  if (v['statut'] == 'entretien') return const EtatVehicule('entretien', 'En entretien');
  if (v['statut'] == 'hors_service') return const EtatVehicule('hors_service', 'Hors service');
  final actives =
      locations.where((l) => '${l['vehicule_id']}' == '${v['id']}' && statutsActifs.contains(l['statut'])).toList()
        ..sort((a, b) => '${a['date_debut']}'.compareTo('${b['date_debut']}'));
  for (final l in actives) {
    if (enRetard(l, aujourdhui)) {
      return EtatVehicule('retard', 'Retour en retard (prévu le ${jourCourt('${l['date_fin']}')})', location: l);
    }
    if (l['statut'] == 'en_cours') {
      return EtatVehicule('loue', 'Loué jusqu’au ${jourCourt('${l['date_fin']}')}', location: l);
    }
    // réservé et la date de départ est arrivée : le client vient chercher le véhicule
    if ('${l['date_debut']}'.compareTo(aujourdhui) <= 0 && '${l['date_fin']}'.compareTo(aujourdhui) >= 0) {
      return EtatVehicule('a_remettre', 'Clés à remettre (réservé)', location: l);
    }
  }
  final prochaine = actives.where((l) => '${l['date_debut']}'.compareTo(aujourdhui) > 0).firstOrNull;
  if (prochaine != null) {
    return EtatVehicule(
      'reserve_plus_tard',
      'Libre · réservé dès le ${jourCourt('${prochaine['date_debut']}')}',
      location: prochaine,
    );
  }
  return const EtatVehicule('disponible', 'Disponible');
}

/// Location « en cours » dont la date de retour est dépassée.
bool enRetard(JsonRow l, String aujourdhui) =>
    l['statut'] == 'en_cours' && '${l['date_fin']}'.compareTo(aujourdhui) < 0;
