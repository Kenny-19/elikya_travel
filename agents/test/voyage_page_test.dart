// Écran Voyage : paiements, caisse du jour, étapes visa, alertes, filtres.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/data/location_logic.dart' show jourCle;
import 'package:elikya_agents/profile.dart';
import 'package:elikya_agents/ui/pages/voyage_page.dart';
import 'package:elikya_agents/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_remote.dart';

final vente = Profile(
  nom: 'Chargé de Vente',
  role: 'Vente',
  userId: 'u1',
  permissions: {'voyage': true, 'caisse': true},
);
final pa = Profile(nom: 'Assistante', role: 'PA', userId: 'u3', permissions: {'voyage': true});
String jour(int d) => jourCle(DateTime.now().add(Duration(days: d)));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late FakeRemote remote;
  late DataService data;

  setUp(() {
    remote = FakeRemote();
    remote.server
      ..['clients'] = [
        {'id': 'c1', 'nom': 'Patrick Mwamba', 'telephone': '+243971234567'},
        {'id': 'c2', 'nom': 'Grace Ilunga', 'telephone': '+243993345588'},
      ]
      ..['dossiers'] = [
        {
          'id': 'd1',
          'ref': 'ELK-1',
          'client_id': 'c1',
          'type': 'billet',
          'destination': 'Lubumbashi → Johannesburg',
          'date_depart': jour(2),
          'date_retour': jour(9),
          'compagnie': 'Airlink',
          'montant': 520,
          'devise_id': 1,
          'statut': 'confirme',
          'cree_le': '2026-11-20T08:00:00Z',
        },
        {
          'id': 'd2',
          'ref': 'ELK-2',
          'client_id': 'c2',
          'type': 'visa',
          'pays': 'Afrique du Sud',
          'etape_visa': 'depose',
          'montant': 180,
          'devise_id': 1,
          'statut': 'confirme',
          'cree_le': '2026-11-21T08:00:00Z',
        },
        {
          'id': 'd3',
          'ref': 'ELK-3',
          'client_id': 'c2',
          'type': 'hotel',
          'hotel': 'Pullman',
          'destination': 'Kinshasa',
          'montant': 300,
          'devise_id': 1,
          'statut': 'termine',
          'cree_le': '2026-11-01T08:00:00Z',
        },
      ]
      ..['paiements'] = [
        {
          'id': 'p1',
          'source_type': 'dossier',
          'source_id': 'd1',
          'mode': 'especes',
          'montant': 200,
          'devise_id': 1,
          'cree_le': '2026-11-20T09:00:00Z',
        },
        {
          'id': 'p2',
          'source_type': 'dossier',
          'source_id': 'd2',
          'mode': 'mobile_money',
          'montant': 180,
          'devise_id': 1,
          'cree_le': '2026-11-21T09:00:00Z',
        },
      ]
      ..['caisse_sessions'] = [
        {'id': 's1', 'jour': jour(0), 'solde_ouverture': 100, 'statut': 'ouverte', 'agent_id': 'u1'},
      ]
      ..['mouvements_caisse'] = [];
    data = DataService(LocalDb(NativeDatabase.memory()), remote, probeEvery: const Duration(hours: 1));
  });
  tearDown(() => data.local.close());

  Future<void> pump(WidgetTester t, Profile p) async {
    await t.binding.setSurfaceSize(const Size(1500, 1200));
    await t.pumpWidget(
      MaterialApp(
        theme: Elk.theme(Brightness.light),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: VoyagePage(data: data, profile: p),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('liste « en cours » : paiement, alerte départ proche non soldé, bouton visa', (t) async {
    await pump(t, vente);
    expect(find.textContaining('Patrick Mwamba'), findsWidgets);
    expect(find.text('Payé 200 \$ · reste 320 \$'), findsOneWidget);
    expect(
      find.textContaining('partent bientôt').evaluate().isNotEmpty ||
          find.textContaining('part bientôt').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.textContaining('reste 320 \$'), findsWidgets);
    expect(find.text('Passer à : En traitement'), findsOneWidget, reason: 'visa soldé → bouton d’étape');
    expect(find.textContaining('Pullman'), findsNothing, reason: 'dossier effectué hors de la liste « en cours »');
  });

  testWidgets('encaisser en espèces → paiement + ajout à la caisse du jour', (t) async {
    await pump(t, vente);
    await t.tap(find.widgetWithText(FilledButton, 'Encaisser').first);
    await t.pumpAndSettle();
    expect(find.text('Ajouter aussi à ma caisse du jour'), findsOneWidget);
    await t.tap(find.text('Enregistrer le paiement'));
    await t.pumpAndSettle();
    final p = remote.server['paiements']!.last;
    expect([p['source_id'], p['montant'], p['mode'], p['recu_par']], ['d1', 320, 'especes', 'u1']);
    final m = remote.server['mouvements_caisse']!.single;
    expect(
      [m['session_id'], m['sens'], m['montant'], m['source_id'], m['module']],
      ['s1', 'entree', 320, p['id'], 'Voyage'],
    );
    expect(find.text('Tout est payé'), findsWidgets);
  });

  testWidgets('sans droit caisse : pas de proposition d’ajout à la caisse', (t) async {
    await pump(t, pa);
    await t.tap(find.widgetWithText(FilledButton, 'Encaisser').first);
    await t.pumpAndSettle();
    expect(find.text('Ajouter aussi à ma caisse du jour'), findsNothing);
    await t.tap(find.text('Mobile money'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Montant reçu'), '100');
    await t.enterText(find.widgetWithText(TextFormField, 'N° de transaction (facultatif)'), 'MP123');
    await t.tap(find.text('Enregistrer le paiement'));
    await t.pumpAndSettle();
    final p = remote.server['paiements']!.last;
    expect([p['mode'], p['montant'], p['reference']], ['mobile_money', 100, 'MP123']);
    expect(remote.server['mouvements_caisse'], isEmpty);
  });

  testWidgets('visa : passer à l’étape suivante', (t) async {
    await pump(t, vente);
    await t.tap(find.text('Passer à : En traitement'));
    await t.pumpAndSettle();
    expect(remote.server['dossiers']![1]['etape_visa'], 'en_traitement');
  });

  testWidgets('filtres : effectués / annulés', (t) async {
    await pump(t, vente);
    await t.tap(find.text('Effectués / annulés'));
    await t.pumpAndSettle();
    expect(find.textContaining('Pullman'), findsOneWidget);
    expect(find.text('Voyage effectué'), findsOneWidget);
  });

  testWidgets('nouveau dossier : champs selon le service, bouton bloqué sans client', (t) async {
    await pump(t, vente);
    await t.tap(find.text('Nouveau dossier'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Trajet'), findsOneWidget);
    expect(find.text('Aller simple'), findsOneWidget);
    await t.tap(find.text('Visa'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Pays du visa'), findsOneWidget);
    expect(find.text('Aller simple'), findsNothing);
    final b = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enregistrer'));
    expect(b.onPressed, isNull);
  });
}
