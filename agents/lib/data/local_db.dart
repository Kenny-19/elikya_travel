// Base LOCALE de secours (SQLite via drift).
// Elle ne sert que si Supabase est injoignable : copie des lignes lues en ligne,
// + file des saisies faites hors ligne (outbox) + saisies refusées à la synchro.
//
// Les lignes sont stockées en JSON par (table, id) : pas de second schéma à maintenir,
// toute nouvelle colonne côté Supabase est copiée automatiquement.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

typedef JsonRow = Map<String, dynamic>;

/// Copie locale des lignes Supabase.
class LocalRows extends Table {
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get data => text()(); // JSON de la ligne
  @override
  Set<Column> get primaryKey => {tbl, rowId};
}

/// Saisies faites hors ligne, rejouées dans l'ordre au retour du réseau.
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get op => text()(); // insert | update
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get payload => text()(); // JSON : ligne complète (insert) ou modification (update)
  DateTimeColumn get at => dateTime().withDefault(currentDateAndTime)();
}

/// Saisies refusées par la base en ligne (contrainte, droits…) : gardées pour être vues.
class FailedOps extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get op => text()();
  TextColumn get tbl => text()();
  TextColumn get rowId => text()();
  TextColumn get payload => text()();
  TextColumn get error => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  DateTimeColumn get at => dateTime()();
}

@DriftDatabase(tables: [LocalRows, Outbox, FailedOps])
class LocalDb extends _$LocalDb {
  LocalDb([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'elikya_local'));

  @override
  int get schemaVersion => 1;

  // ---- copie des lignes ----
  Future<List<JsonRow>> rowsOf(String table) async {
    final rows = await (select(localRows)..where((r) => r.tbl.equals(table))).get();
    return rows.map((r) => jsonDecode(r.data) as JsonRow).toList();
  }

  Future<JsonRow?> rowOf(String table, String id) async {
    final r = await (select(localRows)..where((x) => x.tbl.equals(table) & x.rowId.equals(id))).getSingleOrNull();
    return r == null ? null : jsonDecode(r.data) as JsonRow;
  }

  Future<void> putRows(String table, String key, List<JsonRow> rows) async {
    if (rows.isEmpty) return;
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        localRows,
        rows.map((r) => LocalRowsCompanion.insert(tbl: table, rowId: '${r[key]}', data: jsonEncode(r))),
      ),
    );
  }

  Future<void> deleteRow(String table, String id) =>
      (delete(localRows)..where((x) => x.tbl.equals(table) & x.rowId.equals(id))).go();

  // ---- file d'attente ----
  Future<void> enqueue(String op, String table, String id, JsonRow payload) =>
      into(outbox).insert(OutboxCompanion.insert(op: op, tbl: table, rowId: id, payload: jsonEncode(payload)));

  Future<List<OutboxData>> pending() => (select(outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();

  Future<void> dequeue(int seq) => (delete(outbox)..where((o) => o.seq.equals(seq))).go();

  Future<void> markFailed(OutboxData item, String error, String code) => into(failedOps).insert(
    FailedOpsCompanion.insert(
      op: item.op,
      tbl: item.tbl,
      rowId: item.rowId,
      payload: item.payload,
      error: error,
      code: Value(code),
      at: item.at,
    ),
  );

  Future<List<FailedOp>> failed() => (select(failedOps)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();

  Future<void> clearFailed() => delete(failedOps).go();

  Future<int> countPending() async => (await select(outbox).get()).length;
  Future<int> countFailed() async => (await select(failedOps).get()).length;
}
