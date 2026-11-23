// Écrans Caisse et Mobile Money : affichage, saisies en ligne et hors ligne.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/profile.dart';
import 'package:elikya_agents/ui/pages/caisse_page.dart';
import 'package:elikya_agents/ui/pages/momo_page.dart';
import 'package:elikya_agents/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'fake_remote.dart';

final agent = Profile(
  nom: 'Agent A',
  role: 'Chargé de Vente',
  userId: 'u1',
  permissions: {'caisse': true, 'momo': true},
);
final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late FakeRemote remote;
  late DataService data;

  Future<void> pump(WidgetTester t, Widget page) async {
    await t.binding.setSurfaceSize(const Size(1400, 1000));
    await t.pumpWidget(
      MaterialApp(
        theme: Elk.theme(Brightness.light),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: page),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t, String label, String text) async {
    await t.enterText(find.widgetWithText(TextFormField, label), text);
  }

  setUp(() {
    remote = FakeRemote();
    remote.server['caisse_sessions']!.first['jour'] = today;
    remote.server['mouvements_caisse']!.add({
      'id': 'm2',
      'session_id': 's1',
      'sens': 'sortie',
      'libelle': 'Carburant',
      'montant': 2800,
      'devise_id': 2,
      'cree_le': '2026-11-22T09:00:00+00:00',
    });
    remote.server['momo_comptes'] = [
      {'id': 1, 'operateur': 'airtel', 'solde': 2310},
      {'id': 2, 'operateur': 'mpesa', 'solde': 1820},
    ];
    remote.server['momo_transactions'] = [
      {
        'id': 't1',
        'type': 'depot',
        'compte_id': 1,
        'montant': 120,
        'frais': 1.2,
        'statut': 'reussi',
        'client_tel': '+243970000010',
        'cree_le': '2026-11-20T10:00:00+00:00',
      },
      {
        'id': 't2',
        'type': 'retrait',
        'compte_id': 2,
        'montant': 150,
        'frais': 1.5,
        'statut': 'en_attente',
        'client_tel': '+243970000011',
        'cree_le': '2026-11-21T10:00:00+00:00',
      },
    ];
    data = DataService(LocalDb(NativeDatabase.memory()), remote, probeEvery: const Duration(hours: 1));
  });
  tearDown(() => data.local.close());

  group('Caisse', () {
    testWidgets('solde théorique en USD, CDF converti au taux', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      // ouverture 100 + entrée 50 $ − sortie 2 800 FC (= 1 $) → 149 $
      expect(find.text(Elk.money(100, 'USD')), findsOneWidget);
      expect(find.text(Elk.money(50, 'USD')), findsOneWidget);
      expect(find.text(Elk.money(1, 'USD')), findsOneWidget);
      expect(find.text(Elk.money(149, 'USD')), findsOneWidget);
      expect(find.text('Carburant'), findsOneWidget);
      expect(find.text('Ouverte'), findsOneWidget);
    });

    testWidgets('mouvement en ligne puis hors ligne', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      await t.tap(find.text('Mouvement'));
      await t.pumpAndSettle();
      await fill(t, 'Libellé', 'Visa ELK-2042');
      await fill(t, 'Montant', '180');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(remote.server['mouvements_caisse']!.length, 3);
      expect(remote.server['mouvements_caisse']!.last['agent_id'], 'u1');
      expect(find.text('Visa ELK-2042'), findsOneWidget);
      expect(find.text(Elk.money(329, 'USD')), findsOneWidget);

      remote.net = false;
      await t.tap(find.text('Mouvement'));
      await t.pumpAndSettle();
      await fill(t, 'Libellé', 'Taxi');
      await fill(t, 'Montant', '10');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.textContaining('hors ligne, sera synchronisé'), findsOneWidget);
      expect(find.text('Taxi'), findsOneWidget, reason: 'visible depuis la copie locale');
      expect(remote.server['mouvements_caisse']!.length, 3);
      expect(data.status.value.pending, 1);
      data.dispose(); // arrête le test de reconnexion périodique
    });

    testWidgets('clôture avec écart', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      await t.tap(find.text('Clôturer'));
      await t.pumpAndSettle();
      await fill(t, 'Solde compté (USD)', '140');
      await t.tap(find.widgetWithText(FilledButton, 'Clôturer'));
      await t.pumpAndSettle();
      expect(remote.server['caisse_sessions']!.first['statut'], 'cloturee');
      expect(remote.server['caisse_sessions']!.first['solde_cloture'], 140);
      expect(find.text('Manquant'), findsOneWidget);
      expect(find.text('Clôturée'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Mouvement')).onPressed,
        isNull,
        reason: 'plus de saisie sur une session clôturée',
      );
    });

    testWidgets('pas de 2e session le même jour pour le même agent', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      await t.tap(find.text('Ouvrir une session'));
      await t.pumpAndSettle();
      await fill(t, 'Solde d’ouverture (USD)', '0');
      await t.tap(find.text('Ouvrir'));
      await t.pumpAndSettle();
      expect(find.text('Une session existe déjà pour ce jour et cet agent.'), findsOneWidget);
      expect(remote.server['caisse_sessions']!.length, 1);
    });
  });

  group('Mobile Money', () {
    test('début de période', () {
      final now = DateTime(2026, 11, 22, 15, 30);
      expect(sinceOf('tout', now), isNull);
      expect(DateTime.parse(sinceOf('jour', now)!).toLocal(), DateTime(2026, 11, 22));
      expect(DateTime.parse(sinceOf('semaine', now)!).toLocal(), DateTime(2026, 11, 16));
    });

    testWidgets('soldes, KPIs, filtre par type', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      expect(find.text('Airtel Money'), findsWidgets);
      expect(find.text(Elk.money(2310, 'USD')), findsOneWidget);
      expect(find.text(Elk.money(120, 'USD')), findsWidgets); // volume réussi = dépôt seul
      expect(find.text('2 transactions'), findsOneWidget);

      await t.tap(find.text('Tous types'));
      await t.pumpAndSettle();
      await t.tap(find.text('Retrait').last);
      await t.pumpAndSettle();
      expect(find.text('1 transaction'), findsOneWidget);
      expect(find.text('+243970000011'), findsOneWidget);
      expect(find.text('+243970000010'), findsNothing);
    });

    testWidgets('transaction en attente → réussie', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      await t.tap(find.text('En attente'));
      await t.pumpAndSettle();
      await t.tap(find.text('Réussi').last);
      await t.pumpAndSettle();
      expect(remote.server['momo_transactions']![1]['statut'], 'reussi');
    });

    testWidgets('nouvelle transaction et relevé de solde', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      await t.tap(find.text('Nouvelle transaction'));
      await t.pumpAndSettle();
      await fill(t, 'Montant (USD)', '75,5');
      await fill(t, 'Téléphone client', '+243990000000');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final last = remote.server['momo_transactions']!.last;
      expect(last['montant'], 75.5);
      expect(last['frais'], 0);
      expect(last['agent_id'], 'u1');

      await t.tap(find.text('Relevé').first);
      await t.pumpAndSettle();
      await fill(t, 'Nouveau solde relevé (USD)', '2500');
      await t.tap(find.text('Mettre à jour'));
      await t.pumpAndSettle();
      expect(remote.server['momo_comptes']!.first['solde'], 2500);
      expect(find.text(Elk.money(2500, 'USD')), findsOneWidget);
    });
  });
}
