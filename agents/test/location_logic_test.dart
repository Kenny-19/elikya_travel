import 'package:elikya_agents/data/location_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hilux = {'id': 'v1', 'tarif_jour': 80, 'tarif_chauffeur_jour': 25, 'statut': 'disponible'};
  final locs = [
    {'id': 'l1', 'vehicule_id': 'v1', 'date_debut': '2026-11-20', 'date_fin': '2026-11-24', 'statut': 'en_cours'},
    {'id': 'l2', 'vehicule_id': 'v1', 'date_debut': '2026-12-01', 'date_fin': '2026-12-03', 'statut': 'reservee'},
    {'id': 'l3', 'vehicule_id': 'v1', 'date_debut': '2026-11-26', 'date_fin': '2026-11-28', 'statut': 'annulee'},
    {'id': 'l4', 'vehicule_id': 'v2', 'date_debut': '2026-11-26', 'date_fin': '2026-11-28', 'statut': 'reservee'},
  ];

  test('jours : départ et retour inclus, minimum 1', () {
    expect(joursLocation('2026-11-01', '2026-11-03'), 3);
    expect(joursLocation('2026-11-05', '2026-11-05'), 1);
    expect(joursLocation('2026-12-30', '2027-01-02'), 4);
    expect(joursLocation('2026-03-28', '2026-03-30'), 3, reason: 'changement d’heure sans effet');
  });

  test('montant conseillé avec / sans chauffeur', () {
    expect(montantConseille(hilux, '2026-11-01', '2026-11-03', false), 240);
    expect(montantConseille(hilux, '2026-11-01', '2026-11-03', true), 315);
  });

  test('conflits : chevauchement sur le même véhicule actif seulement', () {
    expect(conflitLocation(locs, 'v1', '2026-11-24', '2026-11-25')?['id'], 'l1', reason: 'jour de retour inclus');
    expect(conflitLocation(locs, 'v1', '2026-11-25', '2026-11-30'), isNull, reason: 'annulée ignorée');
    expect(conflitLocation(locs, 'v1', '2026-11-30', '2026-12-01')?['id'], 'l2');
    expect(conflitLocation(locs, 'v2', '2026-11-20', '2026-11-25'), isNull, reason: 'autre véhicule');
    expect(
      conflitLocation(locs, 'v1', '2026-12-01', '2026-12-02', saufId: 'l2'),
      isNull,
      reason: 'modification de soi-même',
    );
  });

  test('état du véhicule', () {
    expect(etatVehicule(hilux, locs, '2026-11-22').code, 'loue');
    expect(etatVehicule(hilux, locs, '2026-11-22').libelle, 'Loué jusqu’au 24/11');
    // l1 encore « en cours » après sa date de retour → en retard (le véhicule n'est pas libre)
    expect(etatVehicule(hilux, locs, '2026-11-26').code, 'retard');
    expect(etatVehicule(hilux, locs, '2026-11-26').libelle, 'Retour en retard (prévu le 24/11)');
    final rendu = [
      for (final l in locs) l['id'] == 'l1' ? {...l, 'statut': 'terminee'} : l,
    ];
    expect(etatVehicule(hilux, rendu, '2026-11-26').code, 'reserve_plus_tard');
    expect(etatVehicule(hilux, rendu, '2026-11-26').libelle, 'Libre · réservé dès le 01/12');
    expect(etatVehicule(hilux, rendu, '2026-12-10').code, 'disponible');
    expect(etatVehicule({...hilux, 'statut': 'entretien'}, locs, '2026-11-22').code, 'entretien');
    final reserveAujourdhui = [
      {'id': 'x', 'vehicule_id': 'v1', 'date_debut': '2026-12-05', 'date_fin': '2026-12-06', 'statut': 'reservee'},
    ];
    expect(
      etatVehicule(hilux, reserveAujourdhui, '2026-12-05').code,
      'a_remettre',
      reason: 'réservation qui commence aujourd’hui',
    );
  });

  test('retard de retour', () {
    expect(enRetard(locs[0], '2026-11-25'), isTrue);
    expect(enRetard(locs[0], '2026-11-24'), isFalse);
    expect(enRetard(locs[1], '2026-12-10'), isFalse, reason: 'réservée, pas en cours');
  });

  test('clé de jour', () => expect(jourCle(DateTime(2026, 3, 7)), '2026-03-07'));
}
