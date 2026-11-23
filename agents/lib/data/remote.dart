// Accès à la base EN LIGNE (Supabase). Isolé derrière une interface pour pouvoir
// tester la logique en ligne / hors ligne sans réseau.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_db.dart';

/// Supabase injoignable (pas de réseau, délai dépassé…) → bascule sur la base locale.
class RemoteNetworkError implements Exception {
  RemoteNetworkError(this.cause);
  final Object cause;
  @override
  String toString() => 'Base en ligne injoignable ($cause)';
}

/// Supabase a répondu mais a refusé (contrainte, droits…) → erreur à montrer.
class RemoteError implements Exception {
  RemoteError(this.message, [this.code = '']);
  final String message;
  final String code;
  @override
  String toString() => message;
}

/// Paramètres de lecture, communs au en ligne et au local.
class Query {
  const Query({
    this.embed = const [],
    this.eq = const {},
    this.gte = const {},
    this.lte = const {},
    this.orderBy,
    this.ascending = true,
    this.limit,
  });
  final List<String> embed; // ex. ['clients(nom)', 'devises(code)']
  final Map<String, Object?> eq;
  final Map<String, Object> gte;
  final Map<String, Object> lte;
  final String? orderBy;
  final bool ascending;
  final int? limit;
}

abstract class Remote {
  Future<List<JsonRow>> select(String table, Query q);
  Future<JsonRow?> insert(String table, JsonRow row);
  Future<void> upsert(String table, JsonRow row, String key);
  Future<JsonRow?> update(String table, String key, Object id, JsonRow patch);
  Future<dynamic> rpc(String fn);
  Future<void> ping();
}

class SupabaseRemote implements Remote {
  SupabaseRemote(this.client, {this.timeout = const Duration(seconds: 8)});
  final SupabaseClient client;
  final Duration timeout;

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(timeout);
    } on PostgrestException catch (e) {
      throw RemoteError(e.message, e.code ?? '');
    } on AuthException catch (e) {
      // jeton expiré qu'on ne peut pas rafraîchir faute de réseau, etc.
      if (e is AuthRetryableFetchException) throw RemoteNetworkError(e);
      throw RemoteError(e.message, e.code ?? '');
    } catch (e) {
      throw RemoteNetworkError(e); // SocketException, ClientException, TimeoutException…
    }
  }

  @override
  Future<List<JsonRow>> select(String table, Query q) => _run(() async {
    PostgrestFilterBuilder<List<JsonRow>> b = client.from(table).select(['*', ...q.embed].join(','));
    q.eq.forEach((k, v) => b = v == null ? b.isFilter(k, null) : b.eq(k, v));
    q.gte.forEach((k, v) => b = b.gte(k, v));
    q.lte.forEach((k, v) => b = b.lte(k, v));
    PostgrestTransformBuilder<List<JsonRow>> t = b;
    if (q.orderBy != null) t = t.order(q.orderBy!, ascending: q.ascending);
    if (q.limit != null) t = t.limit(q.limit!);
    return await t;
  });

  @override
  Future<JsonRow?> insert(String table, JsonRow row) => _run(() async {
    final r = await client.from(table).insert(row).select();
    return r.isEmpty ? null : r.first;
  });

  @override
  Future<void> upsert(String table, JsonRow row, String key) =>
      _run(() async => await client.from(table).upsert(row, onConflict: key));

  @override
  Future<JsonRow?> update(String table, String key, Object id, JsonRow patch) => _run(() async {
    final r = await client.from(table).update(patch).eq(key, id).select();
    return r.isEmpty ? null : r.first;
  });

  @override
  Future<dynamic> rpc(String fn) => _run(() async => await client.rpc(fn));

  @override
  Future<void> ping() => _run(() async => await client.from('devises').select('id').limit(1));
}
