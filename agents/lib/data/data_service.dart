// Accès aux données unique de l'app agents — même règle que web/js/data.js :
//   Supabase EN LIGNE = PRIORITAIRE. SQLite LOCAL = SECOURS si Supabase est injoignable.
//   - lecture en ligne réussie → copie locale mise à jour ;
//   - hors ligne → lecture locale, écritures mises en file (outbox) ;
//   - retour du réseau → file rejouée dans l'ordre (upsert sur l'id → pas de doublon).
// Les écrans passent TOUJOURS par ce service, jamais par Supabase directement.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'local_db.dart';
import 'remote.dart';
import 'tables.dart';

class NetStatus {
  const NetStatus({required this.online, this.pending = 0, this.failed = 0, this.synced = false});
  final bool online;
  final int pending; // saisies en attente d'envoi
  final int failed; // saisies refusées par la base en ligne
  final bool synced; // vient de se resynchroniser (les écrans se rechargent)
}

class DataResult<T> {
  const DataResult(this.data, {this.error, this.code = '', this.offline = false});
  final T? data;
  final String? error;
  final String code;
  final bool offline; // true = servi / enregistré sur la base locale
  bool get ok => error == null;
}

class DataService {
  DataService(this.local, this.remote, {this.probeEvery = const Duration(seconds: 15), this.warmLimit = 1000});

  final LocalDb local;
  final Remote remote;
  final Duration probeEvery;
  final int warmLimit;

  final status = ValueNotifier(const NetStatus(online: true));
  Timer? _probe;
  bool _syncing = false;
  final _uuid = const Uuid();

  bool get online => status.value.online;

  void _emit({bool? online, bool synced = false, int? pending, int? failed}) {
    final s = status.value;
    status.value = NetStatus(
      online: online ?? s.online,
      pending: pending ?? s.pending,
      failed: failed ?? s.failed,
      synced: synced,
    );
  }

  void goOffline() {
    if (online) _emit(online: false);
    _probe ??= Timer.periodic(probeEvery, (_) => probe());
  }

  Future<void> probe() async {
    try {
      await remote.ping();
    } on RemoteNetworkError {
      return;
    } on RemoteError {
      // répond (même avec une erreur) → le réseau est là
    }
    await _goOnline();
  }

  Future<void> _goOnline() async {
    _probe?.cancel();
    _probe = null;
    final was = online;
    final hadPending = status.value.pending > 0;
    _emit(online: true);
    await sync();
    if (online) _emit(synced: !was || hadPending);
  }

  // ------------------------------------------------------------------ lecture
  Future<DataResult<List<JsonRow>>> select(String table, [Query q = const Query()]) async {
    if (online) {
      try {
        final rows = await remote.select(table, q);
        await _cache(table, rows);
        return DataResult(rows);
      } on RemoteError catch (e) {
        return DataResult(const [], error: e.message, code: e.code);
      } on RemoteNetworkError {
        goOffline();
      }
    }
    return DataResult(await _localSelect(table, q), offline: true);
  }

  Future<DataResult<JsonRow>> selectOne(String table, [Query q = const Query()]) async {
    final r = await select(table, q);
    return DataResult(
      r.data?.isNotEmpty == true ? r.data!.first : null,
      error: r.error,
      code: r.code,
      offline: r.offline,
    );
  }

  Future<List<JsonRow>> _localSelect(String table, Query q) async {
    var rows = (await local.rowsOf(table)).where((r) {
      for (final e in q.eq.entries) {
        if ('${r[e.key]}' != '${e.value}') return false;
      }
      for (final e in q.gte.entries) {
        if (r[e.key] == null || _cmp(r[e.key], e.value) < 0) return false;
      }
      for (final e in q.lte.entries) {
        if (r[e.key] == null || _cmp(r[e.key], e.value) > 0) return false;
      }
      return true;
    }).toList();
    if (q.orderBy != null) {
      final c = q.orderBy!, dir = q.ascending ? 1 : -1;
      rows.sort((a, b) => _cmp(a[c], b[c]) * dir);
    }
    if (q.limit != null && rows.length > q.limit!) rows = rows.sublist(0, q.limit!);
    return _embedLocal(table, rows, q.embed);
  }

  static int _cmp(Object? a, Object? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  Future<List<JsonRow>> _embedLocal(String table, List<JsonRow> rows, List<String> specs) async {
    final rels = tables[table]?.rels ?? const {};
    for (final spec in specs) {
      final m = RegExp(r'^(\w+)\((.*)\)$').firstMatch(spec.replaceAll(' ', ''));
      if (m == null || !rels.containsKey(m[1])) continue;
      final alias = m[1]!;
      final (target, fk) = rels[alias]!;
      final fields = m[2] == '*' ? null : m[2]!.split(',');
      final byKey = {for (final x in await local.rowsOf(target)) '${x[keyOf(target)]}': x};
      rows = [
        for (final r in rows)
          {
            ...r,
            alias: switch (byKey['${r[fk]}']) {
              null => null,
              final t when fields == null => t,
              final t => {for (final f in fields) f: t[f]},
            },
          },
      ];
    }
    return rows;
  }

  // ------------------------------------------------------------------ écriture
  Future<DataResult<JsonRow>> insert(String table, JsonRow row) async {
    final key = keyOf(table);
    row = {...row};
    if (row[key] == null && key == 'id') row['id'] = _uuid.v4();
    if (tables[table]?.ts == true) row['cree_le'] ??= DateTime.now().toUtc().toIso8601String();
    if (online) {
      try {
        final saved = await remote.insert(table, row) ?? row;
        await _cache(table, [saved]);
        return DataResult(saved);
      } on RemoteError catch (e) {
        return DataResult(null, error: e.message, code: e.code);
      } on RemoteNetworkError {
        goOffline();
      }
    }
    await _cache(table, [row]);
    await local.enqueue('insert', table, '${row[key]}', row);
    await refreshCounts();
    return DataResult(row, offline: true);
  }

  Future<DataResult<JsonRow>> update(String table, Object id, JsonRow patch) async {
    final key = keyOf(table);
    if (online) {
      try {
        final saved = await remote.update(table, key, id, patch);
        if (saved != null) await _cache(table, [saved]);
        return DataResult(saved);
      } on RemoteError catch (e) {
        return DataResult(null, error: e.message, code: e.code);
      } on RemoteNetworkError {
        goOffline();
      }
    }
    final merged = {...?await local.rowOf(table, '$id'), ...patch, key: id};
    await _cache(table, [merged]);
    await local.enqueue('update', table, '$id', patch);
    await refreshCounts();
    return DataResult(merged, offline: true);
  }

  Future<dynamic> rpc(String fn) => remote.rpc(fn);

  // ------------------------------------------------------------------ synchro
  Future<void> refreshCounts() async => _emit(pending: await local.countPending(), failed: await local.countFailed());

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      for (final it in await local.pending()) {
        final key = keyOf(it.tbl);
        final payload = jsonDecode(it.payload) as JsonRow;
        try {
          if (it.op == 'insert') {
            await remote.upsert(it.tbl, payload, key);
          } else {
            await remote.update(it.tbl, key, _typedId(it.tbl, it.rowId), payload);
          }
        } on RemoteNetworkError {
          goOffline();
          break;
        } on RemoteError catch (e) {
          // refusé (doublon, droits…) : mis de côté et retiré de la copie locale
          await local.markFailed(it, e.message, e.code);
          if (it.op == 'insert') await local.deleteRow(it.tbl, it.rowId);
        }
        await local.dequeue(it.seq);
      }
    } finally {
      _syncing = false;
      await refreshCounts();
    }
  }

  /// Les ids "serial" (devises, momo_comptes…) sont des entiers côté Supabase.
  Object _typedId(String table, String id) => int.tryParse(id) ?? id;

  /// Copie locale des données récentes, pour être prêt en cas de coupure.
  Future<void> warmup() async {
    for (final e in tables.entries) {
      if (!online) return;
      final order = e.value.order ?? (e.value.ts ? 'cree_le' : null);
      await select(e.key, Query(orderBy: order, ascending: false, limit: warmLimit));
    }
  }

  Future<void> _cache(String table, List<JsonRow> rows) async {
    if (!tables.containsKey(table) || rows.isEmpty) return;
    final rels = tables[table]!.rels;
    final clean = [
      for (final r in rows)
        {
          for (final e in r.entries)
            if (!rels.containsKey(e.key) && !tables.containsKey(e.key)) e.key: e.value,
        },
    ];
    await local.putRows(table, keyOf(table), clean);
  }

  // ------------------------------------------------------------------ profil (rôle)
  static const _profileTable = '_profil';

  Future<void> saveProfile(String authUid, JsonRow profile) => local.putRows(_profileTable, 'auth_uid', [
    {...profile, 'auth_uid': authUid},
  ]);

  Future<JsonRow?> cachedProfile(String authUid) => local.rowOf(_profileTable, authUid);

  void dispose() {
    _probe?.cancel();
    status.dispose();
  }
}
