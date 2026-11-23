// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $LocalRowsTable extends LocalRows with TableInfo<$LocalRowsTable, LocalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tblMeta = const VerificationMeta('tbl');
  @override
  late final GeneratedColumn<String> tbl = GeneratedColumn<String>(
    'tbl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tbl, rowId, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_rows';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tbl')) {
      context.handle(_tblMeta, tbl.isAcceptableOrUnknown(data['tbl']!, _tblMeta));
    } else if (isInserting) {
      context.missing(_tblMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(_rowIdMeta, rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta));
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('data')) {
      context.handle(_dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tbl, rowId};
  @override
  LocalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRow(
      tbl: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tbl'])!,
      rowId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}row_id'])!,
      data: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}data'])!,
    );
  }

  @override
  $LocalRowsTable createAlias(String alias) {
    return $LocalRowsTable(attachedDatabase, alias);
  }
}

class LocalRow extends DataClass implements Insertable<LocalRow> {
  final String tbl;
  final String rowId;
  final String data;
  const LocalRow({required this.tbl, required this.rowId, required this.data});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tbl'] = Variable<String>(tbl);
    map['row_id'] = Variable<String>(rowId);
    map['data'] = Variable<String>(data);
    return map;
  }

  LocalRowsCompanion toCompanion(bool nullToAbsent) {
    return LocalRowsCompanion(tbl: Value(tbl), rowId: Value(rowId), data: Value(data));
  }

  factory LocalRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRow(
      tbl: serializer.fromJson<String>(json['tbl']),
      rowId: serializer.fromJson<String>(json['rowId']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tbl': serializer.toJson<String>(tbl),
      'rowId': serializer.toJson<String>(rowId),
      'data': serializer.toJson<String>(data),
    };
  }

  LocalRow copyWith({String? tbl, String? rowId, String? data}) =>
      LocalRow(tbl: tbl ?? this.tbl, rowId: rowId ?? this.rowId, data: data ?? this.data);
  LocalRow copyWithCompanion(LocalRowsCompanion data) {
    return LocalRow(
      tbl: data.tbl.present ? data.tbl.value : this.tbl,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRow(')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tbl, rowId, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRow && other.tbl == this.tbl && other.rowId == this.rowId && other.data == this.data);
}

class LocalRowsCompanion extends UpdateCompanion<LocalRow> {
  final Value<String> tbl;
  final Value<String> rowId;
  final Value<String> data;
  final Value<int> rowid;
  const LocalRowsCompanion({
    this.tbl = const Value.absent(),
    this.rowId = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRowsCompanion.insert({
    required String tbl,
    required String rowId,
    required String data,
    this.rowid = const Value.absent(),
  }) : tbl = Value(tbl),
       rowId = Value(rowId),
       data = Value(data);
  static Insertable<LocalRow> custom({
    Expression<String>? tbl,
    Expression<String>? rowId,
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tbl != null) 'tbl': tbl,
      if (rowId != null) 'row_id': rowId,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRowsCompanion copyWith({Value<String>? tbl, Value<String>? rowId, Value<String>? data, Value<int>? rowid}) {
    return LocalRowsCompanion(
      tbl: tbl ?? this.tbl,
      rowId: rowId ?? this.rowId,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tbl.present) {
      map['tbl'] = Variable<String>(tbl.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRowsCompanion(')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tblMeta = const VerificationMeta('tbl');
  @override
  late final GeneratedColumn<String> tbl = GeneratedColumn<String>(
    'tbl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [seq, op, tbl, rowId, payload, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxData> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(_seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('tbl')) {
      context.handle(_tblMeta, tbl.isAcceptableOrUnknown(data['tbl']!, _tblMeta));
    } else if (isInserting) {
      context.missing(_tblMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(_rowIdMeta, rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta));
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      seq: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      op: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}op'])!,
      tbl: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tbl'])!,
      rowId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}row_id'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      at: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}at'])!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int seq;
  final String op;
  final String tbl;
  final String rowId;
  final String payload;
  final DateTime at;
  const OutboxData({
    required this.seq,
    required this.op,
    required this.tbl,
    required this.rowId,
    required this.payload,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['op'] = Variable<String>(op);
    map['tbl'] = Variable<String>(tbl);
    map['row_id'] = Variable<String>(rowId);
    map['payload'] = Variable<String>(payload);
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      seq: Value(seq),
      op: Value(op),
      tbl: Value(tbl),
      rowId: Value(rowId),
      payload: Value(payload),
      at: Value(at),
    );
  }

  factory OutboxData.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      seq: serializer.fromJson<int>(json['seq']),
      op: serializer.fromJson<String>(json['op']),
      tbl: serializer.fromJson<String>(json['tbl']),
      rowId: serializer.fromJson<String>(json['rowId']),
      payload: serializer.fromJson<String>(json['payload']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'op': serializer.toJson<String>(op),
      'tbl': serializer.toJson<String>(tbl),
      'rowId': serializer.toJson<String>(rowId),
      'payload': serializer.toJson<String>(payload),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  OutboxData copyWith({int? seq, String? op, String? tbl, String? rowId, String? payload, DateTime? at}) => OutboxData(
    seq: seq ?? this.seq,
    op: op ?? this.op,
    tbl: tbl ?? this.tbl,
    rowId: rowId ?? this.rowId,
    payload: payload ?? this.payload,
    at: at ?? this.at,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      seq: data.seq.present ? data.seq.value : this.seq,
      op: data.op.present ? data.op.value : this.op,
      tbl: data.tbl.present ? data.tbl.value : this.tbl,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      payload: data.payload.present ? data.payload.value : this.payload,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('seq: $seq, ')
          ..write('op: $op, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seq, op, tbl, rowId, payload, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.seq == this.seq &&
          other.op == this.op &&
          other.tbl == this.tbl &&
          other.rowId == this.rowId &&
          other.payload == this.payload &&
          other.at == this.at);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> seq;
  final Value<String> op;
  final Value<String> tbl;
  final Value<String> rowId;
  final Value<String> payload;
  final Value<DateTime> at;
  const OutboxCompanion({
    this.seq = const Value.absent(),
    this.op = const Value.absent(),
    this.tbl = const Value.absent(),
    this.rowId = const Value.absent(),
    this.payload = const Value.absent(),
    this.at = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.seq = const Value.absent(),
    required String op,
    required String tbl,
    required String rowId,
    required String payload,
    this.at = const Value.absent(),
  }) : op = Value(op),
       tbl = Value(tbl),
       rowId = Value(rowId),
       payload = Value(payload);
  static Insertable<OutboxData> custom({
    Expression<int>? seq,
    Expression<String>? op,
    Expression<String>? tbl,
    Expression<String>? rowId,
    Expression<String>? payload,
    Expression<DateTime>? at,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (op != null) 'op': op,
      if (tbl != null) 'tbl': tbl,
      if (rowId != null) 'row_id': rowId,
      if (payload != null) 'payload': payload,
      if (at != null) 'at': at,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? seq,
    Value<String>? op,
    Value<String>? tbl,
    Value<String>? rowId,
    Value<String>? payload,
    Value<DateTime>? at,
  }) {
    return OutboxCompanion(
      seq: seq ?? this.seq,
      op: op ?? this.op,
      tbl: tbl ?? this.tbl,
      rowId: rowId ?? this.rowId,
      payload: payload ?? this.payload,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (tbl.present) {
      map['tbl'] = Variable<String>(tbl.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('seq: $seq, ')
          ..write('op: $op, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

class $FailedOpsTable extends FailedOps with TableInfo<$FailedOpsTable, FailedOp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FailedOpsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tblMeta = const VerificationMeta('tbl');
  @override
  late final GeneratedColumn<String> tbl = GeneratedColumn<String>(
    'tbl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [seq, op, tbl, rowId, payload, error, code, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'failed_ops';
  @override
  VerificationContext validateIntegrity(Insertable<FailedOp> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(_seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('tbl')) {
      context.handle(_tblMeta, tbl.isAcceptableOrUnknown(data['tbl']!, _tblMeta));
    } else if (isInserting) {
      context.missing(_tblMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(_rowIdMeta, rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta));
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('error')) {
      context.handle(_errorMeta, error.isAcceptableOrUnknown(data['error']!, _errorMeta));
    } else if (isInserting) {
      context.missing(_errorMeta);
    }
    if (data.containsKey('code')) {
      context.handle(_codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  FailedOp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FailedOp(
      seq: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      op: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}op'])!,
      tbl: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tbl'])!,
      rowId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}row_id'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      error: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}error'])!,
      code: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      at: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}at'])!,
    );
  }

  @override
  $FailedOpsTable createAlias(String alias) {
    return $FailedOpsTable(attachedDatabase, alias);
  }
}

class FailedOp extends DataClass implements Insertable<FailedOp> {
  final int seq;
  final String op;
  final String tbl;
  final String rowId;
  final String payload;
  final String error;
  final String code;
  final DateTime at;
  const FailedOp({
    required this.seq,
    required this.op,
    required this.tbl,
    required this.rowId,
    required this.payload,
    required this.error,
    required this.code,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['op'] = Variable<String>(op);
    map['tbl'] = Variable<String>(tbl);
    map['row_id'] = Variable<String>(rowId);
    map['payload'] = Variable<String>(payload);
    map['error'] = Variable<String>(error);
    map['code'] = Variable<String>(code);
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  FailedOpsCompanion toCompanion(bool nullToAbsent) {
    return FailedOpsCompanion(
      seq: Value(seq),
      op: Value(op),
      tbl: Value(tbl),
      rowId: Value(rowId),
      payload: Value(payload),
      error: Value(error),
      code: Value(code),
      at: Value(at),
    );
  }

  factory FailedOp.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FailedOp(
      seq: serializer.fromJson<int>(json['seq']),
      op: serializer.fromJson<String>(json['op']),
      tbl: serializer.fromJson<String>(json['tbl']),
      rowId: serializer.fromJson<String>(json['rowId']),
      payload: serializer.fromJson<String>(json['payload']),
      error: serializer.fromJson<String>(json['error']),
      code: serializer.fromJson<String>(json['code']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'op': serializer.toJson<String>(op),
      'tbl': serializer.toJson<String>(tbl),
      'rowId': serializer.toJson<String>(rowId),
      'payload': serializer.toJson<String>(payload),
      'error': serializer.toJson<String>(error),
      'code': serializer.toJson<String>(code),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  FailedOp copyWith({
    int? seq,
    String? op,
    String? tbl,
    String? rowId,
    String? payload,
    String? error,
    String? code,
    DateTime? at,
  }) => FailedOp(
    seq: seq ?? this.seq,
    op: op ?? this.op,
    tbl: tbl ?? this.tbl,
    rowId: rowId ?? this.rowId,
    payload: payload ?? this.payload,
    error: error ?? this.error,
    code: code ?? this.code,
    at: at ?? this.at,
  );
  FailedOp copyWithCompanion(FailedOpsCompanion data) {
    return FailedOp(
      seq: data.seq.present ? data.seq.value : this.seq,
      op: data.op.present ? data.op.value : this.op,
      tbl: data.tbl.present ? data.tbl.value : this.tbl,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      payload: data.payload.present ? data.payload.value : this.payload,
      error: data.error.present ? data.error.value : this.error,
      code: data.code.present ? data.code.value : this.code,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FailedOp(')
          ..write('seq: $seq, ')
          ..write('op: $op, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('error: $error, ')
          ..write('code: $code, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seq, op, tbl, rowId, payload, error, code, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FailedOp &&
          other.seq == this.seq &&
          other.op == this.op &&
          other.tbl == this.tbl &&
          other.rowId == this.rowId &&
          other.payload == this.payload &&
          other.error == this.error &&
          other.code == this.code &&
          other.at == this.at);
}

class FailedOpsCompanion extends UpdateCompanion<FailedOp> {
  final Value<int> seq;
  final Value<String> op;
  final Value<String> tbl;
  final Value<String> rowId;
  final Value<String> payload;
  final Value<String> error;
  final Value<String> code;
  final Value<DateTime> at;
  const FailedOpsCompanion({
    this.seq = const Value.absent(),
    this.op = const Value.absent(),
    this.tbl = const Value.absent(),
    this.rowId = const Value.absent(),
    this.payload = const Value.absent(),
    this.error = const Value.absent(),
    this.code = const Value.absent(),
    this.at = const Value.absent(),
  });
  FailedOpsCompanion.insert({
    this.seq = const Value.absent(),
    required String op,
    required String tbl,
    required String rowId,
    required String payload,
    required String error,
    this.code = const Value.absent(),
    required DateTime at,
  }) : op = Value(op),
       tbl = Value(tbl),
       rowId = Value(rowId),
       payload = Value(payload),
       error = Value(error),
       at = Value(at);
  static Insertable<FailedOp> custom({
    Expression<int>? seq,
    Expression<String>? op,
    Expression<String>? tbl,
    Expression<String>? rowId,
    Expression<String>? payload,
    Expression<String>? error,
    Expression<String>? code,
    Expression<DateTime>? at,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (op != null) 'op': op,
      if (tbl != null) 'tbl': tbl,
      if (rowId != null) 'row_id': rowId,
      if (payload != null) 'payload': payload,
      if (error != null) 'error': error,
      if (code != null) 'code': code,
      if (at != null) 'at': at,
    });
  }

  FailedOpsCompanion copyWith({
    Value<int>? seq,
    Value<String>? op,
    Value<String>? tbl,
    Value<String>? rowId,
    Value<String>? payload,
    Value<String>? error,
    Value<String>? code,
    Value<DateTime>? at,
  }) {
    return FailedOpsCompanion(
      seq: seq ?? this.seq,
      op: op ?? this.op,
      tbl: tbl ?? this.tbl,
      rowId: rowId ?? this.rowId,
      payload: payload ?? this.payload,
      error: error ?? this.error,
      code: code ?? this.code,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (tbl.present) {
      map['tbl'] = Variable<String>(tbl.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FailedOpsCompanion(')
          ..write('seq: $seq, ')
          ..write('op: $op, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('error: $error, ')
          ..write('code: $code, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $LocalRowsTable localRows = $LocalRowsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $FailedOpsTable failedOps = $FailedOpsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [localRows, outbox, failedOps];
}

typedef $$LocalRowsTableCreateCompanionBuilder = LocalRowsCompanion Function({
  required String tbl,
  required String rowId,
  required String data,
  Value<int> rowid,
});
typedef $$LocalRowsTableUpdateCompanionBuilder = LocalRowsCompanion Function({
  Value<String> tbl,
  Value<String> rowId,
  Value<String> data,
  Value<int> rowid,
});

class $$LocalRowsTableFilterComposer extends Composer<_$LocalDb, $LocalRowsTable> {
  $$LocalRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tbl => $composableBuilder(column: $table.tbl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(column: $table.data, builder: (column) => ColumnFilters(column));
}

class $$LocalRowsTableOrderingComposer extends Composer<_$LocalDb, $LocalRowsTable> {
  $$LocalRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tbl =>
      $composableBuilder(column: $table.tbl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => ColumnOrderings(column));
}

class $$LocalRowsTableAnnotationComposer extends Composer<_$LocalDb, $LocalRowsTable> {
  $$LocalRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tbl => $composableBuilder(column: $table.tbl, builder: (column) => column);

  GeneratedColumn<String> get rowId => $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get data => $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$LocalRowsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LocalRowsTable,
          LocalRow,
          $$LocalRowsTableFilterComposer,
          $$LocalRowsTableOrderingComposer,
          $$LocalRowsTableAnnotationComposer,
          $$LocalRowsTableCreateCompanionBuilder,
          $$LocalRowsTableUpdateCompanionBuilder,
          (LocalRow, BaseReferences<_$LocalDb, $LocalRowsTable, LocalRow>),
          LocalRow,
          PrefetchHooks Function()
        > {
  $$LocalRowsTableTableManager(_$LocalDb db, $LocalRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$LocalRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$LocalRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$LocalRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> tbl = const Value.absent(),
            Value<String> rowId = const Value.absent(),
            Value<String> data = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => LocalRowsCompanion(tbl: tbl, rowId: rowId, data: data, rowid: rowid),
          createCompanionCallback: ({
            required String tbl,
            required String rowId,
            required String data,
            Value<int> rowid = const Value.absent(),
          }) => LocalRowsCompanion.insert(tbl: tbl, rowId: rowId, data: data, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalRowsTable, LocalRow>(table),
                  BaseReferences<_$LocalDb, $LocalRowsTable, LocalRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LocalRowsTable,
      LocalRow,
      $$LocalRowsTableFilterComposer,
      $$LocalRowsTableOrderingComposer,
      $$LocalRowsTableAnnotationComposer,
      $$LocalRowsTableCreateCompanionBuilder,
      $$LocalRowsTableUpdateCompanionBuilder,
      (LocalRow, BaseReferences<_$LocalDb, $LocalRowsTable, LocalRow>),
      LocalRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> seq,
  required String op,
  required String tbl,
  required String rowId,
  required String payload,
  Value<DateTime> at,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> seq,
  Value<String> op,
  Value<String> tbl,
  Value<String> rowId,
  Value<String> payload,
  Value<DateTime> at,
});

class $$OutboxTableFilterComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get op => $composableBuilder(column: $table.op, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tbl => $composableBuilder(column: $table.tbl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get at => $composableBuilder(column: $table.at, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get op => $composableBuilder(column: $table.op, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tbl =>
      $composableBuilder(column: $table.tbl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq => $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get op => $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get tbl => $composableBuilder(column: $table.tbl, builder: (column) => column);

  GeneratedColumn<String> get rowId => $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get at => $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxData, BaseReferences<_$LocalDb, $OutboxTable, OutboxData>),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$LocalDb db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> seq = const Value.absent(),
            Value<String> op = const Value.absent(),
            Value<String> tbl = const Value.absent(),
            Value<String> rowId = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<DateTime> at = const Value.absent(),
          }) => OutboxCompanion(seq: seq, op: op, tbl: tbl, rowId: rowId, payload: payload, at: at),
          createCompanionCallback: ({
            Value<int> seq = const Value.absent(),
            required String op,
            required String tbl,
            required String rowId,
            required String payload,
            Value<DateTime> at = const Value.absent(),
          }) => OutboxCompanion.insert(seq: seq, op: op, tbl: tbl, rowId: rowId, payload: payload, at: at),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxData>(table),
                  BaseReferences<_$LocalDb, $OutboxTable, OutboxData>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$LocalDb, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $$FailedOpsTableCreateCompanionBuilder = FailedOpsCompanion Function({
  Value<int> seq,
  required String op,
  required String tbl,
  required String rowId,
  required String payload,
  required String error,
  Value<String> code,
  required DateTime at,
});
typedef $$FailedOpsTableUpdateCompanionBuilder = FailedOpsCompanion Function({
  Value<int> seq,
  Value<String> op,
  Value<String> tbl,
  Value<String> rowId,
  Value<String> payload,
  Value<String> error,
  Value<String> code,
  Value<DateTime> at,
});

class $$FailedOpsTableFilterComposer extends Composer<_$LocalDb, $FailedOpsTable> {
  $$FailedOpsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get op => $composableBuilder(column: $table.op, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tbl => $composableBuilder(column: $table.tbl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get code => $composableBuilder(column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get at => $composableBuilder(column: $table.at, builder: (column) => ColumnFilters(column));
}

class $$FailedOpsTableOrderingComposer extends Composer<_$LocalDb, $FailedOpsTable> {
  $$FailedOpsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get op => $composableBuilder(column: $table.op, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tbl =>
      $composableBuilder(column: $table.tbl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => ColumnOrderings(column));
}

class $$FailedOpsTableAnnotationComposer extends Composer<_$LocalDb, $FailedOpsTable> {
  $$FailedOpsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq => $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get op => $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get tbl => $composableBuilder(column: $table.tbl, builder: (column) => column);

  GeneratedColumn<String> get rowId => $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get error => $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get code => $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<DateTime> get at => $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$FailedOpsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $FailedOpsTable,
          FailedOp,
          $$FailedOpsTableFilterComposer,
          $$FailedOpsTableOrderingComposer,
          $$FailedOpsTableAnnotationComposer,
          $$FailedOpsTableCreateCompanionBuilder,
          $$FailedOpsTableUpdateCompanionBuilder,
          (FailedOp, BaseReferences<_$LocalDb, $FailedOpsTable, FailedOp>),
          FailedOp,
          PrefetchHooks Function()
        > {
  $$FailedOpsTableTableManager(_$LocalDb db, $FailedOpsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$FailedOpsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$FailedOpsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$FailedOpsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String> tbl = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> error = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
              }) => FailedOpsCompanion(
                seq: seq,
                op: op,
                tbl: tbl,
                rowId: rowId,
                payload: payload,
                error: error,
                code: code,
                at: at,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required String op,
                required String tbl,
                required String rowId,
                required String payload,
                required String error,
                Value<String> code = const Value.absent(),
                required DateTime at,
              }) => FailedOpsCompanion.insert(
                seq: seq,
                op: op,
                tbl: tbl,
                rowId: rowId,
                payload: payload,
                error: error,
                code: code,
                at: at,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FailedOpsTable, FailedOp>(table),
                  BaseReferences<_$LocalDb, $FailedOpsTable, FailedOp>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FailedOpsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $FailedOpsTable,
      FailedOp,
      $$FailedOpsTableFilterComposer,
      $$FailedOpsTableOrderingComposer,
      $$FailedOpsTableAnnotationComposer,
      $$FailedOpsTableCreateCompanionBuilder,
      $$FailedOpsTableUpdateCompanionBuilder,
      (FailedOp, BaseReferences<_$LocalDb, $FailedOpsTable, FailedOp>),
      FailedOp,
      PrefetchHooks Function()
    >;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$LocalRowsTableTableManager get localRows => $$LocalRowsTableTableManager(_db, _db.localRows);
  $$OutboxTableTableManager get outbox => $$OutboxTableTableManager(_db, _db.outbox);
  $$FailedOpsTableTableManager get failedOps => $$FailedOpsTableTableManager(_db, _db.failedOps);
}
