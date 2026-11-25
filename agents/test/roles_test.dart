// Le menu de l'app agents suit les permissions du rôle (roles.permissions).
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/profile.dart';
import 'package:elikya_agents/ui/shell.dart';
import 'package:elikya_agents/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_remote.dart';

Profile _p(String role, Map<String, dynamic> perms) =>
    Profile(nom: 'Test $role', role: role, userId: 'u1', permissions: perms);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('Profile.can : direction = tout, sinon permission par module', () {
    final dg = _p('DG', {'all': true});
    final momo = _p('Agent Mobile Money', {'momo': true, 'caisse': true});
    expect(dg.can('voyage') && dg.can('fourniture'), isTrue);
    expect(momo.can('momo'), isTrue);
    expect(momo.can('voyage'), isFalse);
  });

  Future<DataService> pumpShell(WidgetTester t, Profile p) async {
    final remote = FakeRemote()
      ..server['dossiers'] = [
        {
          'id': 'd1',
          'ref': 'ELK-2041',
          'type': 'billet',
          'montant': 520,
          'devise_id': 1,
          'statut': 'confirme',
          'cree_le': '2026-11-22T08:00:00Z',
        },
      ];
    final data = DataService(LocalDb(NativeDatabase.memory()), remote, probeEvery: const Duration(hours: 1));
    await t.binding.setSurfaceSize(const Size(1400, 900));
    await t.pumpWidget(
      MaterialApp(
        theme: Elk.theme(Brightness.light),
        home: Shell(data: data, profile: p, onSignOut: () {}),
      ),
    );
    await t.pumpAndSettle();
    return data;
  }

  testWidgets('agent Mobile Money : Caisse + Mobile Money seulement', (t) async {
    final data = await pumpShell(t, _p('Agent Mobile Money', {'momo': true, 'caisse': true}));
    expect(find.text('Caisse'), findsWidgets);
    expect(find.text('Mobile Money'), findsOneWidget);
    expect(find.text('Voyage'), findsNothing);
    expect(find.text('Fourniture'), findsNothing);
    await data.local.close();
  });

  testWidgets('chargé de vente : Voyage ouvert avec les dossiers', (t) async {
    final data = await pumpShell(
      t,
      _p('Chargé de Vente', {'voyage': true, 'caisse': true, 'clients': true, 'fourniture': true}),
    );
    expect(find.text('Mobile Money'), findsNothing);
    expect(find.text('Fourniture'), findsOneWidget);
    expect(find.textContaining('ELK-2041'), findsOneWidget);
    expect(find.text('Confirmé'), findsOneWidget);
    await data.local.close();
  });
}
