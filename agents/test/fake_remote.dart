// Faux Supabase en mémoire, partagé par les tests.
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/data/remote.dart';
import 'package:elikya_agents/data/tables.dart';

class FakeRemote implements Remote {
  bool net = true;
  final server = <String, List<JsonRow>>{
    'devises': [
      {'id': 1, 'code': 'USD', 'taux': 1, 'actif': true},
      {'id': 2, 'code': 'CDF', 'taux': 2800, 'actif': true},
    ],
    'users': [
      {'id': 'u1', 'nom': 'Agent A', 'auth_id': 'auth1'},
    ],
    'caisse_sessions': [
      {'id': 's1', 'jour': '2026-11-22', 'solde_ouverture': 100, 'statut': 'ouverte', 'agent_id': 'u1'},
    ],
    'mouvements_caisse': [
      {
        'id': 'm1',
        'session_id': 's1',
        'sens': 'entree',
        'libelle': 'Seed',
        'montant': 50,
        'devise_id': 1,
        'cree_le': '2026-11-22T08:00:00+00:00',
      },
    ],
    'momo_comptes': [
      {'id': 1, 'operateur': 'airtel', 'solde': 2310},
    ],
  };

  void _check() {
    if (!net) throw RemoteNetworkError('Failed host lookup');
  }

  List<JsonRow> _t(String t) => server.putIfAbsent(t, () => []);

  @override
  Future<List<JsonRow>> select(String table, Query q) async {
    _check();
    final rels = tables[table]?.rels ?? const {};
    var rows = _t(table)
        .where((r) => q.eq.entries.every((e) => '${r[e.key]}' == '${e.value}'))
        .where((r) => q.gte.entries.every((e) => r[e.key] != null && '${r[e.key]}'.compareTo('${e.value}') >= 0))
        .where((r) => q.lte.entries.every((e) => r[e.key] != null && '${r[e.key]}'.compareTo('${e.value}') <= 0))
        .map((r) {
          final o = {...r};
          // jointures « alias(champs) » comme PostgREST, d'après lib/data/tables.dart
          for (final spec in q.embed) {
            final m = RegExp(r'^(\w+)\((.*)\)$').firstMatch(spec)!;
            final (target, fk) = rels[m[1]]!;
            final t = _t(target).where((x) => '${x[keyOf(target)]}' == '${r[fk]}').firstOrNull;
            o[m[1]!] = t == null ? null : {for (final f in m[2]!.split(',')) f: t[f]};
          }
          return o;
        })
        .toList();
    if (q.orderBy != null) {
      rows.sort((a, b) => '${a[q.orderBy]}'.compareTo('${b[q.orderBy]}') * (q.ascending ? 1 : -1));
    }
    if (q.limit != null && rows.length > q.limit!) rows = rows.sublist(0, q.limit!);
    return rows;
  }

  @override
  Future<JsonRow?> insert(String table, JsonRow row) async {
    _check();
    if (_t(table).any((x) => x['id'] == row['id'])) throw RemoteError('duplicate key', '23505');
    _t(table).add({...row});
    return {...row};
  }

  @override
  Future<void> upsert(String table, JsonRow row, String key) async {
    _check();
    if (table == 'caisse_sessions' &&
        _t(table).any((x) => x['id'] != row['id'] && x['jour'] == row['jour'] && x['agent_id'] == row['agent_id'])) {
      throw RemoteError('duplicate key value violates unique constraint', '23505');
    }
    final ex = _t(table).where((x) => x[key] == row[key]).firstOrNull;
    ex == null ? _t(table).add({...row}) : ex.addAll(row);
  }

  @override
  Future<JsonRow?> update(String table, String key, Object id, JsonRow patch) async {
    _check();
    final ex = _t(table).where((x) => x[key] == id).firstOrNull;
    ex?.addAll(patch);
    return ex == null ? null : {...ex};
  }

  @override
  Future<dynamic> rpc(String fn) async => _check();

  @override
  Future<void> ping() async => _check();
}
