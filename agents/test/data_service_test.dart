// Logique « en ligne prioritaire, SQLite local en secours » avec un faux Supabase en mémoire.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/data/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeRemote remote;
  late DataService data;

  setUp(() {
    remote = FakeRemote();
    data = DataService(LocalDb(NativeDatabase.memory()), remote, probeEvery: const Duration(hours: 1));
  });
  tearDown(() async {
    data.dispose();
    await data.local.close();
  });

  const mvts = Query(embed: ['devises(code)'], eq: {'session_id': 's1'}, orderBy: 'cree_le', ascending: false);

  test('lecture en ligne puis hors ligne depuis la copie SQLite (avec jointure)', () async {
    await data.warmup();
    final r = await data.select('mouvements_caisse', mvts);
    expect(r.offline, isFalse);
    expect(r.data!.single['devises'], {'code': 'USD'});

    remote.net = false;
    final r2 = await data.select('mouvements_caisse', mvts);
    expect(r2.offline, isTrue);
    expect(data.online, isFalse);
    expect(r2.data!.single['libelle'], 'Seed');
    expect(r2.data!.single['devises'], {'code': 'USD'});

    final u = await data.selectOne('users', const Query(eq: {'auth_id': 'auth1'}));
    expect(u.data!['id'], 'u1');
    final d = await data.select('devises', const Query(eq: {'actif': true}, orderBy: 'id'));
    expect(d.data!.map((x) => x['code']), ['USD', 'CDF']);
  });

  test('saisies hors ligne : file, synchro, doublon refusé, pas de double envoi', () async {
    await data.warmup();
    remote.net = false;
    await data.select('devises'); // bascule

    final w = await data.insert('mouvements_caisse', {
      'session_id': 's1',
      'sens': 'sortie',
      'libelle': 'Carburant',
      'montant': 2800,
      'devise_id': 2,
    });
    expect(w.offline, isTrue);
    expect(w.data!['id'], isNotNull);
    expect(w.data!['cree_le'], isNotNull);

    final u = await data.update('caisse_sessions', 's1', {'statut': 'cloturee', 'solde_cloture': 149});
    expect(u.data!['jour'], '2026-11-22');
    expect(u.data!['statut'], 'cloturee');

    final m = await data.update('momo_comptes', 1, {'solde': 2000});
    expect(m.offline, isTrue);

    final loc = await data.select('mouvements_caisse', mvts);
    expect(loc.data!.first['libelle'], 'Carburant');
    expect(loc.data!.first['devises'], {'code': 'CDF'});

    await data.insert('caisse_sessions', {'jour': '2026-11-22', 'agent_id': 'u1', 'solde_ouverture': 0});
    expect(data.status.value.pending, 4);
    expect(remote.server['mouvements_caisse']!.length, 1, reason: 'rien envoyé pendant la coupure');

    var synced = false;
    data.status.addListener(() => synced |= data.status.value.synced);
    remote.net = true;
    await data.probe();

    expect(data.online, isTrue);
    expect(synced, isTrue);
    expect(remote.server['mouvements_caisse']!.length, 2);
    expect(remote.server['caisse_sessions']!.first['statut'], 'cloturee');
    expect(remote.server['momo_comptes']!.first['solde'], 2000, reason: 'id entier retrouvé');
    expect(data.status.value.pending, 0);
    expect(data.status.value.failed, 1);
    expect((await data.local.failed()).single.code, '23505');

    remote.net = false;
    final sess = await data.select('caisse_sessions');
    expect(sess.data!.length, 1, reason: 'session refusée retirée de la copie locale');

    remote.net = true;
    await data.probe();
    await data.sync();
    expect(remote.server['mouvements_caisse']!.length, 2, reason: 'pas de doublon');
  });

  test('erreur métier en ligne : renvoyée telle quelle, pas de bascule', () async {
    remote.server['dossiers'] = [
      {'id': 'd1'},
    ];
    final r = await data.insert('dossiers', {'id': 'd1'});
    expect(r.ok, isFalse);
    expect(r.code, '23505');
    expect(data.online, isTrue);
    expect(data.status.value.pending, 0);
  });

  test('profil mis en cache pour le mode hors ligne', () async {
    await data.saveProfile('auth1', {
      'nom': 'Agent A',
      'permissions': {'momo': true},
    });
    final p = await data.cachedProfile('auth1');
    expect(p!['permissions'], {'momo': true});
  });
}
