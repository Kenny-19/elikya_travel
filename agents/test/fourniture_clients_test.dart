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

  Finder dansDialogue(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

  test('état d’un produit en mots simples', () {
    expect(etatProduit(0, 0, 10).$1, 'Plus rien en stock');
    expect(etatProduit(5, 8, 2).$1, 'Pas assez pour les commandes');
    expect(etatProduit(8, 0, 10).$1, 'Bientôt épuisé');
    expect(etatProduit(240, 25, 20).$1, 'OK');
  });

  group('Fourniture', () {
    testWidgets('s’ouvre sur les commandes à livrer', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      expect(find.text('Société Kamoa'), findsOneWidget);
      expect(find.text('25 × Tuyau PVC Ø110'), findsOneWidget);
      expect(find.text('C’est livré'), findsOneWidget);
      expect(find.text('Voir les commandes terminées (1)'), findsOneWidget, reason: 'l’annulée est rangée');
    });

    testWidgets('stock : disponible, alertes « à recommander »', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Stock'));
      await t.pumpAndSettle();
      expect(find.text('Disponible : 215'), findsOneWidget); // 240 − 25 réservés
      expect(find.text('À recommander : 2 produits'), findsOneWidget);
      expect(find.text('Bientôt épuisé'), findsOneWidget);
      expect(find.text('Plus rien en stock'), findsOneWidget);
    });

    testWidgets('nouvelle commande : − / +, total, alerte de stock', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Nouvelle commande'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('Choisissez le client.'), findsOneWidget, reason: 'aucun client choisi d’avance');
      await t.tap(dansDialogue(find.text('Client')));
      await t.pumpAndSettle();
      await t.tap(find.text('Société Kamoa').last);
      await t.pumpAndSettle();
      // 1er produit du catalogue (tri par code) : Casque EPI-220 à 15 $, 8 disponibles
      await fill(t, 'Quantité', '3');
      await t.pump();
      expect(find.text('Total : ${Elk.money(45, 'USD')}'), findsOneWidget);
      await t.tap(find.byTooltip('Un de plus'));
      await t.pump();
      expect(find.text('Total : ${Elk.money(60, 'USD')}'), findsOneWidget);
      await fill(t, 'Quantité', '9');
      await t.pump();
      expect(find.text('Attention : il n’en reste que 8 de disponible.'), findsOneWidget);
      await fill(t, 'Quantité', '3');
      await t.tap(find.text('Ajouter un autre produit'));
      await t.pumpAndSettle();
      await fill(t, 'Quantité', '2'); // 2e produit
      await t.pump();
      expect(find.text('Total : ${Elk.money(75, 'USD')}'), findsOneWidget);
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final cmd = remote.server['commandes']!.last;
      expect(cmd['total'], 75);
      expect(cmd['statut'], 'a_livrer');
      expect(cmd['client_id'], 'c2');
      expect(remote.server['commande_lignes']!.where((l) => l['commande_id'] == cmd['id']).length, 2);
      expect(find.textContaining('${cmd['ref']}'), findsWidgets); // carte + message de confirmation
    });

    testWidgets('« C’est livré »', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('C’est livré'));
      await t.pumpAndSettle();
      expect(remote.server['commandes']!.first['statut'], 'livree');
      expect(find.text('Aucune commande à livrer. Tout est à jour !'), findsOneWidget);
      // le stock baisse tout seul : 25 tuyaux livrés (240 → 215)
      expect(remote.server['produits']!.firstWhere((p) => p['id'] == 'p1')['stock'], 215);
      await t.tap(find.text('Stock'));
      await t.pumpAndSettle();
      expect(find.text('Disponible : 215'), findsOneWidget, reason: 'plus réservé, et sorti du stock');
    });

    testWidgets('annuler une commande demande confirmation', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Annuler la commande'));
      await t.pumpAndSettle();
      await t.tap(find.text('Non, la garder'));
      await t.pumpAndSettle();
      expect(remote.server['commandes']!.first['statut'], 'a_livrer');
      await t.tap(find.text('Annuler la commande'));
      await t.pumpAndSettle();
      await t.tap(find.text('Oui, annuler'));
      await t.pumpAndSettle();
      expect(remote.server['commandes']!.first['statut'], 'annulee');
    });

    testWidgets('produit : code en double refusé, « Compter le stock »', (t) async {
      await pump(t, FourniturePage(data: data, profile: vente));
      await t.tap(find.text('Stock'));
      await t.pumpAndSettle();
      await t.tap(find.text('Nouveau produit'));
      await t.pumpAndSettle();
      await fill(t, 'Code produit', 'tuy-110');
      await fill(t, 'Nom du produit', 'Doublon');
      await fill(t, 'Prix de vente (USD)', '1');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('Ce code existe déjà'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();

      final compter = find.text('Compter le stock').first; // EPI-220 (tri par code)
      await t.ensureVisible(compter);
      await t.pumpAndSettle();
      await t.tap(compter);
      await t.pumpAndSettle();
      await t.enterText(dansDialogue(find.byType(TextField)), '30');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(remote.server['produits']!.firstWhere((p) => p['ref'] == 'EPI-220')['stock'], 30);
    });
  });

  group('Clients', () {
    testWidgets('cartes, « a acheté pour », recherche', (t) async {
      await pump(t, ClientsPage(data: data, profile: vente));
      expect(find.text('Patrick Mwamba'), findsOneWidget);
      expect(find.text(Elk.money(620, 'USD')), findsOneWidget);
      expect(find.text('2 voyages'), findsOneWidget);
      expect(find.text('1 commande'), findsOneWidget); // Kamoa : l’annulée ne compte pas
      await t.enterText(find.widgetWithText(TextField, 'Chercher un client'), 'kolwezi');
      await t.pumpAndSettle();
      expect(find.text('1 client'), findsOneWidget);
      expect(find.text('Société Kamoa'), findsOneWidget);
      expect(find.text('Patrick Mwamba'), findsNothing);
    });

    testWidgets('meilleurs clients en premier', (t) async {
      await pump(t, ClientsPage(data: data, profile: vente));
      await t.tap(find.text('Meilleurs clients'));
      await t.pumpAndSettle();
      final y1 = t.getTopLeft(find.text('Patrick Mwamba')).dy, y2 = t.getTopLeft(find.text('Société Kamoa')).dy;
      expect(y1 < y2, isTrue, reason: '620 \$ avant 300 \$');
    });

    testWidgets('nouveau client, créé par l’agent connecté', (t) async {
      await pump(t, ClientsPage(data: data, profile: vente));
      await t.tap(find.text('Nouveau client'));
      await t.pumpAndSettle();
      await t.tap(find.text('Une entreprise'));
      await t.pump();
      expect(find.text('Nom de l’entreprise'), findsOneWidget);
      await t.tap(find.text('Une personne'));
      await t.pump();
      await fill(t, 'Nom complet', 'Grace Ilunga');
      await t.tap(find.text('Plus d’informations (facultatif)'));
      await t.pumpAndSettle();
      await fill(t, 'E-mail', 'pas-un-mail');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(find.text('E-mail invalide'), findsOneWidget);
      await fill(t, 'E-mail', 'grace@exemple.cd');
      await t.tap(dansDialogue(find.text('VIP')));
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      final c = remote.server['clients']!.last;
      expect(c['nom'], 'Grace Ilunga');
      expect(c['type'], 'particulier');
      expect(c['segment'], 'VIP');
      expect(c['cree_par'], 'u1');
      expect(c['ville'], 'Lubumbashi');
    });

    testWidgets('rôle sans fourniture : montant partiel signalé, commandes non lues', (t) async {
      await pump(t, ClientsPage(data: data, profile: pa));
      expect(find.textContaining('ne comptent pas les commandes de fourniture'), findsOneWidget);
      expect(find.text(Elk.money(620, 'USD')), findsOneWidget); // le voyage reste compté
      expect(find.text(Elk.money(300, 'USD')), findsNothing);
    });
  });
}
