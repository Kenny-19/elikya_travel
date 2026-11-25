// Écran Location : cartes véhicules, actions en un clic, ajout de véhicule.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/data/location_logic.dart';
import 'package:elikya_agents/profile.dart';
import 'package:elikya_agents/ui/pages/location_page.dart';
import 'package:elikya_agents/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_remote.dart';

final vente = Profile(nom: 'Chargé de Vente', role: 'Vente', userId: 'u1', permissions: {'location': true});

String jour(int decalage) => jourCle(DateTime.now().add(Duration(days: decalage)));

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
        {'id': 'c2', 'nom': 'Société Kamoa', 'telephone': '+243819801122'},
      ]
      ..['vehicules'] = [
        {
          'id': 'v1',
          'immatriculation': '1234AB01',
          'marque': 'Toyota',
          'modele': 'Hilux',
          'places': 5,
          'carburant': 'Diesel',
          'tarif_jour': 80,
          'tarif_chauffeur_jour': 25,
          'statut': 'disponible',
          'actif': true,
        },
        {
          'id': 'v2',
          'immatriculation': '5678CD01',
          'marque': 'Toyota',
          'modele': 'Prado',
          'places': 7,
          'carburant': 'Diesel',
          'tarif_jour': 120,
          'tarif_chauffeur_jour': 30,
          'statut': 'disponible',
          'actif': true,
        },
        {
          'id': 'v3',
          'immatriculation': '9012EF01',
          'marque': 'Toyota',
          'modele': 'Corolla',
          'places': 5,
          'carburant': 'Essence',
          'tarif_jour': 50,
          'tarif_chauffeur_jour': 0,
          'statut': 'entretien',
          'actif': true,
        },
      ]
      ..['locations'] = [
        {
          'id': 'l1',
          'ref': 'LOC-1',
          'client_id': 'c1',
          'vehicule_id': 'v1',
          'date_debut': jour(-2),
          'date_fin': jour(1),
          'statut': 'en_cours',
          'avec_chauffeur': true,
          'chauffeur': 'Jean',
          'montant': 420,
          'devise_id': 1,
          'cree_le': '2026-11-20T08:00:00Z',
        },
        {
          'id': 'l2',
          'ref': 'LOC-2',
          'client_id': 'c2',
          'vehicule_id': 'v2',
          'date_debut': jour(0),
          'date_fin': jour(2),
          'statut': 'reservee',
          'avec_chauffeur': false,
          'montant': 360,
          'devise_id': 1,
          'cree_le': '2026-11-21T08:00:00Z',
        },
      ];
    data = DataService(LocalDb(NativeDatabase.memory()), remote, probeEvery: const Duration(hours: 1));
  });
  tearDown(() => data.local.close());

  Future<void> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1400, 1200));
    await t.pumpWidget(
      MaterialApp(
        theme: Elk.theme(Brightness.light),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: LocationPage(data: data, profile: vente),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('cartes : état clair de chaque véhicule + bon bouton', (t) async {
    await pump(t);
    expect(find.textContaining('Loué jusqu’au'), findsOneWidget); // Hilux en cours
    expect(find.text('En entretien'), findsOneWidget); // Corolla
    expect(find.text('Véhicule rendu'), findsWidgets); // Hilux : carte + ligne
    expect(find.text('Remettre les clés'), findsWidgets); // Prado réservé aujourd'hui
    expect(find.text('Remettre en service'), findsOneWidget);
    expect(find.text('Louer'), findsNothing, reason: 'aucun véhicule libre aujourd’hui');
    expect(find.textContaining('avec chauffeur (Jean)'), findsOneWidget);
  });

  testWidgets('Remettre les clés puis Véhicule rendu', (t) async {
    await pump(t);
    await t.tap(find.widgetWithText(FilledButton, 'Remettre les clés').first);
    await t.pumpAndSettle();
    expect(remote.server['locations']![1]['statut'], 'en_cours');
    await t.tap(find.widgetWithText(FilledButton, 'Véhicule rendu').first);
    await t.pumpAndSettle();
    expect(remote.server['locations']!.where((l) => l['statut'] == 'terminee').length, 1);
    expect(find.widgetWithText(FilledButton, 'Louer'), findsOneWidget, reason: 'le véhicule rendu redevient louable');
  });

  testWidgets('ajouter un véhicule (plaque en double refusée)', (t) async {
    await pump(t);
    await t.tap(find.text('Ajouter un véhicule'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Plaque d’immatriculation'), '1234ab01');
    await t.enterText(find.widgetWithText(TextFormField, 'Marque'), 'Toyota');
    await t.enterText(find.widgetWithText(TextFormField, 'Prix par jour (USD)'), '90');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Ce véhicule existe déjà'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Plaque d’immatriculation'), '3456gh01');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final v = remote.server['vehicules']!.last;
    expect(v['immatriculation'], '3456GH01');
    expect(v['tarif_jour'], 90);
    expect(v['statut'], 'disponible');
    expect(find.text('Louer'), findsOneWidget);
  });

  testWidgets('dialogue Louer : véhicule présélectionné, bouton bloqué tant qu’il manque le client et les dates', (
    t,
  ) async {
    await pump(t);
    await t.tap(find.text('Remettre en service'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Louer'));
    await t.pumpAndSettle();
    expect(find.text('Louer un véhicule'), findsOneWidget);
    expect(find.textContaining('Corolla · 9012EF01'), findsOneWidget);
    final reserver = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Réserver'));
    expect(reserver.onPressed, isNull);
    expect(find.text('Choisir les dates dans le calendrier'), findsOneWidget);
  });
}
