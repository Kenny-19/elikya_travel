import 'package:elikya_agents/data/voyage_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final devises = [
    {'id': 1, 'code': 'USD', 'taux': 1},
    {'id': 2, 'code': 'CDF', 'taux': 2800},
  ];
  final d = {'id': 'd1', 'montant': 500, 'devise_id': 1, 'statut': 'confirme', 'date_depart': '2026-11-27'};

  test('avancement : anciens statuts ramenés à « confirmé »', () {
    expect(avancement({'statut': 'paye'}), 'confirme');
    expect(avancement({'statut': 'en_cours'}), 'confirme');
    expect(avancement({'statut': 'devis'}), 'devis');
    expect(avancement({'statut': 'termine'}), 'termine');
  });

  test('paiement : non payé, acompte (avec CDF converti), soldé, trop perçu', () {
    expect(etatPaiement(d, [], devises).code, 'non_paye');
    expect(etatPaiement(d, [], devises).reste, 500);
    final acompte = [
      {'montant': 200, 'devise_id': 1},
      {'montant': 280000, 'devise_id': 2}, // = 100 $
    ];
    final e = etatPaiement(d, acompte, devises);
    expect([e.code, e.paye, e.reste], ['acompte', 300, 200]);
    expect(
      etatPaiement(d, [
        ...acompte,
        {'montant': 200, 'devise_id': 1},
      ], devises).code,
      'solde',
    );
    expect(
      etatPaiement(d, [
        {'montant': 520, 'devise_id': 1},
      ], devises).code,
      'trop_percu',
    );
  });

  test('dossier en CDF payé en USD', () {
    final cdf = {'montant': 1400000, 'devise_id': 2, 'statut': 'confirme'};
    final e = etatPaiement(cdf, [
      {'montant': 250, 'devise_id': 1},
    ], devises);
    expect([e.code, e.paye, e.reste], ['acompte', 700000, 700000]);
  });

  test('ancien dossier « payé » sans encaissements = soldé ; sans montant', () {
    expect(etatPaiement({...d, 'statut': 'paye'}, [], devises).code, 'solde');
    expect(etatPaiement({...d, 'montant': 0}, [], devises).code, 'sans_montant');
  });

  test('encaissements d’un dossier', () {
    final p = [
      {'source_type': 'dossier', 'source_id': 'd1', 'montant': 1},
      {'source_type': 'commande', 'source_id': 'd1', 'montant': 2},
      {'source_type': 'dossier', 'source_id': 'd2', 'montant': 3},
    ];
    expect(paiementsDe(p, 'd1').map((x) => x['montant']), [1]);
  });

  test('visa : étapes', () {
    expect(etapeVisaSuivante(null), 'depose');
    expect(etapeVisaSuivante('depose'), 'en_traitement');
    expect(etapeVisaSuivante('en_traitement'), isNull);
  });

  test('départ proche non soldé', () {
    final today = DateTime(2026, 11, 25);
    final pNon = etatPaiement(d, [], devises),
        pOk = etatPaiement(d, [
          {'montant': 500, 'devise_id': 1},
        ], devises);
    expect(joursAvantDepart(d, today), 2);
    expect(departProcheNonSolde(d, pNon, today), isTrue);
    expect(departProcheNonSolde(d, pOk, today), isFalse, reason: 'soldé');
    expect(departProcheNonSolde({...d, 'statut': 'annule'}, pNon, today), isFalse);
    expect(departProcheNonSolde({...d, 'date_depart': '2026-12-10'}, pNon, today), isFalse, reason: 'trop loin');
  });
}
