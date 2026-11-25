// Écrans Caisse et Mobile Money (version simplifiée) : affichage, saisies en ligne et hors ligne.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/profile.dart';
import 'package:elikya_agents/ui/navigation.dart';
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
        'cree_le': DateTime.now().toUtc().toIso8601String(), // aujourd'hui
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

  Finder dansDialogue(String texte) => find.descendant(of: find.byType(AlertDialog), matching: find.text(texte));

  group('Caisse', () {
    test('écart de caisse en mots simples', () {
      expect(ecartTexte(149, 149).$1, 'C’est juste ✓');
      expect(ecartTexte(140, 149).$1, 'Il manque ${Elk.money(9, 'USD')}');
      expect(ecartTexte(150, 149).$1, 'Il y a ${Elk.money(1, 'USD')} de trop');
    });

    testWidgets('argent en caisse : USD + CDF converti au taux', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      // départ 100 + reçu 50 $ − sorti 2 800 FC (= 1 $) → 149 $
      expect(find.text('En caisse maintenant'), findsOneWidget);
      expect(find.text(Elk.money(149, 'USD')), findsOneWidget);
      expect(
        find.text('Départ ${Elk.money(100, 'USD')} · reçu + ${Elk.money(50, 'USD')} · sorti − ${Elk.money(1, 'USD')}'),
        findsOneWidget,
      );
      expect(find.text('Carburant'), findsOneWidget);
    });

    testWidgets('argent reçu en ligne, argent sorti hors ligne', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      await t.tap(find.text('Argent reçu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('Choisissez d’où vient l’argent.'), findsOneWidget);
      await t.tap(dansDialogue('Visa'));
      await t.pump();
      await fill(t, 'Montant', '180');
      await t.enterText(
        find.widgetWithText(TextField, 'Détail : nom du client, n° de dossier… (facultatif)'),
        'ELK-2042',
      );
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final m = remote.server['mouvements_caisse']!.last;
      expect(m['libelle'], 'Visa · ELK-2042');
      expect(m['sens'], 'entree');
      expect(m['module'], 'Voyage');
      expect(m['agent_id'], 'u1');
      expect(find.text('Visa · ELK-2042'), findsOneWidget);
      expect(find.text(Elk.money(329, 'USD')), findsOneWidget);

      remote.net = false;
      await t.tap(find.text('Argent sorti'));
      await t.pumpAndSettle();
      await t.tap(dansDialogue('Transport'));
      await t.pump();
      await fill(t, 'Montant', '10');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.textContaining('hors ligne, sera synchronisé'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget, reason: 'visible depuis la copie locale');
      expect(remote.server['mouvements_caisse']!.length, 3);
      expect(data.status.value.pending, 1);
      data.dispose(); // arrête le test de reconnexion périodique
    });

    testWidgets('fermer ma caisse : il manque 9 dollars', (t) async {
      await pump(t, CaissePage(data: data, profile: agent));
      await t.tap(find.text('Fermer ma caisse (fin de journée)'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Argent compté (USD)'), '140');
      await t.pump();
      expect(find.text('Il manque ${Elk.money(9, 'USD')}'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Fermer ma caisse'));
      await t.pumpAndSettle();
      expect(remote.server['caisse_sessions']!.first['statut'], 'cloturee');
      expect(remote.server['caisse_sessions']!.first['solde_cloture'], 140);
      expect(find.text('Caisse fermée pour aujourd’hui'), findsOneWidget);
      expect(find.text('Argent reçu'), findsNothing, reason: 'plus de saisie après la fermeture');
    });

    testWidgets('ouvrir ma caisse le matin', (t) async {
      remote.server['caisse_sessions']!.first['jour'] = '2026-01-02';
      remote.server['caisse_sessions']!.first['statut'] = 'cloturee';
      await pump(t, CaissePage(data: data, profile: agent));
      expect(find.text('Votre caisse n’est pas encore ouverte'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Argent dans la caisse (USD)'), '80');
      await t.tap(find.text('Ouvrir ma caisse'));
      await t.pumpAndSettle();
      final s = remote.server['caisse_sessions']!.last;
      expect(s['jour'], today);
      expect(s['solde_ouverture'], 80);
      expect(find.text('En caisse maintenant'), findsOneWidget);
    });
  });

  group('Mobile Money', () {
    tearDown(() => Navigation.demande.value = null);

    test('début de période', () {
      final now = DateTime(2026, 11, 22, 15, 30);
      expect(sinceOf('tout', now), isNull);
      expect(DateTime.parse(sinceOf('jour', now)!).toLocal(), DateTime(2026, 11, 22));
      expect(DateTime.parse(sinceOf('semaine', now)!).toLocal(), DateTime(2026, 11, 16));
    });

    testWidgets('trois gros boutons, soldes, opérations du jour', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      for (final b in ['Dépôt', 'Retrait', 'Transfert']) {
        expect(find.text(b), findsOneWidget);
      }
      expect(find.text(Elk.money(2310, 'USD')), findsOneWidget);
      expect(find.text('Dépôt · Airtel Money'), findsOneWidget);
      expect(find.textContaining('1 opération ·'), findsOneWidget);
      expect(find.text('À confirmer'), findsOneWidget, reason: 'le retrait en attente d’hier reste visible');
    });

    testWidgets('opération en attente → « C’est passé »', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      await t.tap(find.text('C’est passé'));
      await t.pumpAndSettle();
      expect(remote.server['momo_transactions']![1]['statut'], 'reussi');
      expect(find.text('À confirmer'), findsNothing);
    });

    testWidgets('nouveau dépôt : opérateur obligatoire, puis enregistré', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      await t.tap(find.text('Dépôt'));
      await t.pumpAndSettle();
      expect(find.text('Dépôt mobile money'), findsOneWidget);
      await fill(t, 'Montant (USD)', '75,5');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('Choisissez l’opérateur.'), findsOneWidget);
      await t.tap(dansDialogue('M-Pesa'));
      await t.pump();
      await t.enterText(find.widgetWithText(TextField, 'Numéro'), '+243990000000');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final last = remote.server['momo_transactions']!.last;
      expect(last['type'], 'depot');
      expect(last['compte_id'], 2);
      expect(last['montant'], 75.5);
      expect(last['frais'], 0);
      expect(last['statut'], 'reussi');
      expect(last['client_tel'], '+243990000000');
      expect(last['agent_id'], 'u1');
    });

    testWidgets('transfert pas encore confirmé → en attente', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      await t.tap(find.text('Transfert'));
      await t.pumpAndSettle();
      await t.tap(dansDialogue('Airtel Money'));
      await fill(t, 'Montant (USD)', '40');
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(find.text('Pas encore confirmée (en attente)'), findsOneWidget);
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(remote.server['momo_transactions']!.last['statut'], 'en_attente');
      expect(remote.server['momo_transactions']!.last['type'], 'transfert');
    });

    testWidgets('mettre à jour le solde d’un opérateur', (t) async {
      await pump(t, MomoPage(data: data, profile: agent));
      await t.tap(find.text('Mettre à jour le solde').first);
      await t.pumpAndSettle();
      await fill(t, 'Solde actuel (USD)', '2500');
      await t.tap(find.text('Mettre à jour'));
      await t.pumpAndSettle();
      expect(remote.server['momo_comptes']!.first['solde'], 2500);
      expect(find.text(Elk.money(2500, 'USD')), findsOneWidget);
    });

    testWidgets('bouton « Retrait » de l’accueil : le formulaire s’ouvre directement', (t) async {
      Navigation.aller('momo', 'retrait');
      await pump(t, MomoPage(data: data, profile: agent));
      expect(find.text('Retrait mobile money'), findsOneWidget);
      expect(Navigation.prendreAction('momo'), isNull, reason: 'action consommée une seule fois');
    });
  });
}
