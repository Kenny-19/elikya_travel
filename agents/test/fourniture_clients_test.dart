// Écrans Fourniture et Clients : calculs, saisies, rôles.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/profile.dart';
import 'package:elikya_agents/ui/pages/clients_page.dart';
import 'package:elikya_agents/ui/pages/fourniture_page.dart';
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
  permissions: {'voyage': true, 'fourniture': true, 'clients': true, 'caisse': true},
);
final pa = Profile(nom: 'Assistante', role: 'PA', userId: 'u3', permissions: {'voyage': true, 'clients': true});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late FakeRemote remote;
  late DataService data;

  setUp(() {
    remote = FakeRemote();
    remote.server
      ..['clients'] = [
        {
          'id': 'c1',
          'nom': 'Patrick Mwamba',
          'type': 'particulier',
          'telephone': '+243971234567',
          'ville': 'Lubumbashi',
          'segment': 'VIP',
        },
        {
          'id': 'c2',
          'nom': 'Société Kamoa',
          'type': 'entreprise',
          'telephone': '+243819801122',
          'ville': 'Kolwezi',
          'segment': 'Grand compte',
        },
      ]
      ..['produits'] = [
        {
          'id': 'p1',
          'ref': 'TUY-110',
          'designation': 'Tuyau PVC Ø110',
          'categorie': 'Tuyauterie',
          'stock': 240,
          'prix': 12,
          'seuil_alerte': 20,
          'unite': 'pièce',
          'actif': true,
        },
        {
          'id': 'p2',
          'ref': 'EPI-220',
          'designation': 'Casque de sécurité',
          'categorie': 'Sécurité/EPI',
          'stock': 8,
          'prix': 15,
          'seuil_alerte': 10,
          'unite': 'pièce',
          'actif': true,
        },
        {
          'id': 'p3',
          'ref': 'TEC-512',
          'designation': 'Ruban adhésif',
          'categorie': 'Technique',
          'stock': 0,
          'prix': 3,
          'seuil_alerte': 10,
          'unite': 'pièce',
          'actif': true,
        },
      ]
      ..['commandes'] = [
        {
          'id': 'k1',
          'ref': 'CMD-001',
          'client_id': 'c2',
          'statut': 'a_livrer',
          'total': 300,
          'cree_le': '2026-11-20T10:00:00Z',
        },
        {
          'id': 'k2',
          'ref': 'CMD-002',
          'client_id': 'c2',
          'statut': 'annulee',
          'total': 999,
          'cree_le': '2026-11-19T10:00:00Z',
        },
      ]
      ..['commande_lignes'] = [
        {'id': 'l1', 'commande_id': 'k1', 'produit_id': 'p1', 'quantite': 25, 'prix_unitaire': 12},
        {'id': 'l2', 'commande_id': 'k2', 'produit_id': 'p2', 'quantite': 50, 'prix_unitaire': 15},
      ]
      ..['dossiers'] = [
        {'id': 'd1', 'client_id': 'c1', 'montant': 520, 'devise_id': 1, 'statut': 'confirme'},
        {'id': 'd2', 'client_id': 'c1', 'montant': 280000, 'devise_id': 2, 'statut': 'paye'},
        {'id': 'd3', 'client_id': 'c1', 'montant': 5000, 'devise_id': 1, 'statut': 'annule'},
      ];
    data = DataService(LocalDb(NativeDatabase.memory()), remote, probeEvery: const Duration(hours: 1));
  });
  tearDown(() => data.local.close());

  Future<void> pump(WidgetTester t, Widget page) async {
    await t.binding.setSurfaceSize(const Size(1500, 1100));
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

  Future<void> fill(WidgetTester t, String label, String text) =>
      t.enterText(find.widgetWithText(TextFormField, label).last, text);

  test('réservations : seules les commandes « à livrer » comptent', () {
    final r = reservations(remote.server['commandes']!, remote.server['commande_lignes']!);
    expect(r, {'p1': 25});
  });

  test('CA client : USD + CDF converti, annulés exclus', () {
    final s = statsClients(remote.server['dossiers']!, remote.server['commandes']!, remote.server['devises']!);
    expect(s['c1']!.ca, 620); // 520 $ + 280 000 FC / 2800
    expect(s['c1']!.dossiers, 2);
    expect(s['c2']!.ca, 300); // commande annulée exclue
    expect(s['c2']!.commandes, 1);
  });

  group('Fourniture', () {
    testWidgets('catalogue : réservé, disponible, alertes', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      expect(find.text('TUY-110'), findsOneWidget);
      expect(find.text('215'), findsOneWidget); // 240 − 25 réservés
      expect(find.text('Sous le seuil'), findsWidgets);
      expect(find.text('Rupture'), findsOneWidget);
      expect(find.text(Elk.money(240 * 12 + 8 * 15, 'USD')), findsOneWidget); // valeur du stock
    });

    testWidgets('nouvelle commande : lignes + total', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Commandes'));
      await t.pumpAndSettle();
      expect(find.text('CMD-001'), findsOneWidget);
      await t.tap(find.text('Nouvelle commande'));
      await t.pumpAndSettle();
      await fill(t, 'Quantité', '3');
      await t.pump();
      // 1re ligne = 1er produit du catalogue (tri par réf.) : EPI-220 à 15 $
      expect(find.text('Total : ${Elk.money(45, 'USD')}'), findsOneWidget);
      await t.tap(find.text('Ajouter une ligne'));
      await t.pumpAndSettle();
      await fill(t, 'Quantité', '2'); // 2e ligne
      await t.pump();
      expect(find.text('Total : ${Elk.money(75, 'USD')}'), findsOneWidget);
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final cmd = remote.server['commandes']!.last;
      expect(cmd['total'], 75);
      expect(cmd['statut'], 'a_livrer');
      expect(remote.server['commande_lignes']!.where((l) => l['commande_id'] == cmd['id']).length, 2);
      expect(find.text('${cmd['ref']}'), findsOneWidget);
    });

    testWidgets('commande à livrer → livrée', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Commandes'));
      await t.pumpAndSettle();
      await t.tap(find.text('À livrer').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Livrée').last);
      await t.pumpAndSettle();
      expect(remote.server['commandes']!.first['statut'], 'livree');
    });

    testWidgets('produit : référence en double refusée, inventaire modifiable', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Nouveau produit'));
      await t.pumpAndSettle();
      await fill(t, 'Référence', 'tuy-110');
      await fill(t, 'Désignation', 'Doublon');
      await fill(t, 'Prix unitaire (USD)', '1');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('Cette référence existe déjà'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();

      final edit = find.byTooltip('Modifier / inventaire').first; // EPI-220 (tri par réf.)
      await t.ensureVisible(edit);
      await t.pumpAndSettle();
      await t.tap(edit);
      await t.pumpAndSettle();
      await fill(t, 'Stock relevé', '30');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(remote.server['produits']!.firstWhere((p) => p['ref'] == 'EPI-220')['stock'], 30);
    });
  });

  group('Clients', () {
    testWidgets('liste, CA, recherche', (t) async {
      await pump(t, ClientsPage(data: data, profile: vente));
      expect(find.text('Patrick Mwamba'), findsWidgets);
      expect(find.text(Elk.money(620, 'USD')), findsWidgets);
      expect(find.text(Elk.money(920, 'USD')), findsOneWidget); // CA cumulé total
      await t.enterText(find.widgetWithText(TextField, 'Rechercher'), 'kolwezi');
      await t.pumpAndSettle();
      expect(find.text('1 client'), findsOneWidget);
      expect(find.text('Société Kamoa'), findsOneWidget);
    });

    testWidgets('nouveau client, créé par l’agent connecté', (t) async {
      await pump(t, ClientsPage(data: data, profile: vente));
      await t.tap(find.text('Nouveau client'));
      await t.pumpAndSettle();
      await fill(t, 'Nom', 'Grace Ilunga');
      await fill(t, 'E-mail', 'pas-un-mail');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('E-mail invalide'), findsOneWidget);
      await fill(t, 'E-mail', 'grace@exemple.cd');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final c = remote.server['clients']!.last;
      expect(c['nom'], 'Grace Ilunga');
      expect(c['cree_par'], 'u1');
      expect(c['ville'], 'Lubumbashi');
    });

    testWidgets('rôle sans fourniture : CA partiel signalé, commandes non lues', (t) async {
      await pump(t, ClientsPage(data: data, profile: pa));
      expect(find.textContaining('CA partiel'), findsOneWidget);
      expect(find.text(Elk.money(620, 'USD')), findsWidgets); // le voyage reste compté
      expect(find.text(Elk.money(300, 'USD')), findsNothing);
    });
  });
}
