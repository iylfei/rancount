import 'dart:convert';

import '../../utils/beijing_time.dart';
import '../../utils/account_type_utils.dart';

typedef Json = Map<String, dynamic>;

const reconciliationAnalysisVersion = 3;

/// Reconciliation uses integer minor units; SQLite doubles are converted only
/// at the accounting boundary. Unknown screenshot values remain unknown.
int? moneyCents(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  final text = value.toString().trim().replaceAll(',', '');
  final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) throw const FormatException('金额必须是最多两位小数的数字');
  final cents =
      int.parse(match[2]!) * 100 + int.parse((match[3] ?? '').padRight(2, '0'));
  if (cents > 9007199254740991) throw const FormatException('金额超出范围');
  return match[1] == '-' ? -cents : cents;
}

int storedCents(double amount) {
  if (!amount.isFinite) throw const FormatException('金额无效');
  return moneyCents(amount.toStringAsFixed(2))!;
}

String moneyText(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

DateTime? evidenceTime(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  var text = value.toString().trim().replaceFirst(' ', 'T');
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?',
  ).firstMatch(text);
  if (parts == null) return null;
  final year = int.parse(parts[1]!);
  final month = int.parse(parts[2]!);
  final day = int.parse(parts[3]!);
  final checked = DateTime.utc(year, month, day);
  if (checked.year != year ||
      checked.month != month ||
      checked.day != day ||
      int.parse(parts[4]!) > 23 ||
      int.parse(parts[5]!) > 59 ||
      int.parse(parts[6] ?? '0') > 59) {
    return null;
  }
  // Screenshots and date-only user input are interpreted in Beijing time.
  if (!RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(text)) text += '+08:00';
  return DateTime.tryParse(text)?.toUtc();
}

Json jsonObject(Object? value) => Map<String, dynamic>.from(value as Map);
List<Json> jsonObjects(Object? value) =>
    (value as List? ?? []).map(jsonObject).toList();

Object decodeModelJson(String response) {
  var text = response.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }
  return jsonDecode(text);
}

class ReconciliationAccount {
  final int id;
  final String name;
  final String currency;
  final String type;
  final String? syncId;
  int? actualBalance;
  DateTime balanceAt;
  bool complete;
  String? cardLast4;

  ReconciliationAccount({
    required this.id,
    required this.name,
    required this.currency,
    this.type = 'other',
    this.syncId,
    required this.balanceAt,
    this.actualBalance,
    this.complete = false,
    this.cardLast4,
  });

  bool get isLiability => isLiabilityType(type);

  int displayBalance(int netBalance) => isLiability ? -netBalance : netBalance;

  int? balanceFromInput(String value) {
    final cents = moneyCents(value);
    if (isLiability && cents != null && cents < 0) {
      throw const FormatException('总欠款请填写零或正数');
    }
    return cents == null
        ? null
        : isLiability
        ? -cents
        : cents;
  }

  String deltaText(int delta) => isLiability
      ? '${delta < 0 ? '欠款增加' : '欠款减少'} ${moneyText(delta.abs())}'
      : '${delta > 0 ? '+' : ''}${moneyText(delta)}';

  Json toJson() => {
    'id': id,
    'name': name,
    'currency': currency,
    'type': type,
    'syncId': syncId,
    'actualBalance': actualBalance,
    'balanceAt': balanceAt.toIso8601String(),
    'complete': complete,
    'cardLast4': cardLast4,
  };

  factory ReconciliationAccount.fromJson(Json j) => ReconciliationAccount(
    id: j['id'],
    name: j['name'],
    currency: j['currency'],
    type: j['type'] ?? 'other',
    syncId: j['syncId'],
    actualBalance: j['actualBalance'],
    balanceAt: DateTime.parse(j['balanceAt']),
    complete: j['complete'] == true,
    cardLast4: j['cardLast4'],
  );
}

class StatementRow {
  final String id;
  final int accountId;
  final List<String> sourceIds;
  DateTime? time;
  int? delta;
  int? balanceAfter;
  String description;
  final String? orderId;
  final List<String> warnings;
  final String timePrecision;

  StatementRow({
    required this.id,
    required this.accountId,
    required this.sourceIds,
    this.time,
    this.delta,
    this.balanceAfter,
    this.description = '',
    this.orderId,
    List<String>? warnings,
    this.timePrecision = 'second',
  }) : warnings = warnings ?? [];

  Json toJson() => {
    'id': id,
    'accountId': accountId,
    'sourceIds': sourceIds,
    'time': time?.toIso8601String(),
    'deltaCents': delta,
    'balanceAfterCents': balanceAfter,
    'description': description,
    'orderId': orderId,
    'warnings': warnings,
    'timePrecision': timePrecision,
  };

  factory StatementRow.fromJson(Json j) => StatementRow(
    id: j['id'],
    accountId: j['accountId'],
    sourceIds: List<String>.from(j['sourceIds']),
    time: evidenceTime(j['time']),
    delta: j['deltaCents'],
    balanceAfter: j['balanceAfterCents'],
    description: j['description'] ?? '',
    orderId: j['orderId'],
    warnings: List<String>.from(j['warnings'] ?? []),
    timePrecision: j['timePrecision'] ?? legacyTimePrecision(j),
  );

  bool sameKnownTime(DateTime value) {
    if (time == null) return false;
    final a = beijingTime(time!);
    final b = beijingTime(value);
    if (a.year != b.year || a.month != b.month || a.day != b.day) return false;
    if (timePrecision == 'day') return true;
    if (timePrecision == 'minute') {
      return a.hour == b.hour && a.minute == b.minute;
    }
    return time == value;
  }

  String? get identity {
    if (time == null || delta == null) return null;
    // Truncated order numbers must never become unique keys.
    final order = orderId;
    if (order != null &&
        order.isNotEmpty &&
        !order.contains('…') &&
        !order.contains('...')) {
      return '$accountId:$order:$delta';
    }
    if (balanceAfter == null) return null;
    return '$accountId:${time!.toIso8601String()}:$delta:$balanceAfter:$description';
  }
}

// Older OCR supplied midnight when only a date was visible. Treat this as
// coarse evidence rather than overwriting a recorded exact payment time.
String legacyTimePrecision(Json row) {
  final time = evidenceTime(row['time']);
  if (time != null && (row['sourceIds'] as List? ?? []).isNotEmpty) {
    final local = beijingTime(time);
    if (local.hour == 0 && local.minute == 0 && local.second == 0) return 'day';
  }
  return 'second';
}

class ReconciliationSession {
  final String id;
  final int defaultLedgerId;
  final String? defaultLedgerSyncId;
  final DateTime createdAt;
  DateTime start;
  DateTime end;
  List<ReconciliationAccount> accounts;
  List<Json> sources;
  List<StatementRow> rows;
  List<Json> proposals;
  List<String> issues;
  String summary;
  String? fingerprint;
  int analysisVersion;
  List<Json> matches;
  Json? audit;

  ReconciliationSession({
    required this.id,
    required this.defaultLedgerId,
    this.defaultLedgerSyncId,
    DateTime? createdAt,
    DateTime? start,
    DateTime? end,
    List<ReconciliationAccount>? accounts,
    List<Json>? sources,
    List<StatementRow>? rows,
    List<Json>? proposals,
    List<String>? issues,
    this.summary = '',
    this.fingerprint,
    this.analysisVersion = 0,
    List<Json>? matches,
    this.audit,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       start =
           start ?? beijingDate(beijingNow().year, beijingNow().month).toUtc(),
       end = end ?? DateTime.now().toUtc(),
       accounts = accounts ?? [],
       sources = sources ?? [],
       rows = rows ?? [],
       proposals = proposals ?? [],
       matches = matches ?? [],
       issues = issues ?? [];

  bool get applied => audit != null && audit!['undone'] != true;

  bool hasCurrentAnalysis(String? currentFingerprint) =>
      analysisVersion == reconciliationAnalysisVersion &&
      fingerprint != null &&
      fingerprint == currentFingerprint;

  /// No supplied evidence means no movement. Uploaded but unreadable evidence
  /// remains incomplete, rather than silently becoming an empty statement.
  void refreshEvidenceCompleteness() {
    for (final a in accounts) {
      a.complete =
          sources
              .where((s) => s['accountId'] == a.id)
              .every(
                (s) =>
                    s['recognized'] == true &&
                    (s['warnings'] as List? ?? []).isEmpty,
              ) &&
          rows
              .where((r) => r.accountId == a.id)
              .every(
                (r) => r.time != null && r.delta != null && r.warnings.isEmpty,
              );
    }
  }

  void invalidate() {
    if (applied) throw StateError('请先撤销已应用的修改，或新建对账');
    proposals = [];
    issues = [];
    summary = '';
    fingerprint = null;
    analysisVersion = 0;
    matches = [];
  }

  Json toJson() => {
    'id': id,
    'defaultLedgerId': defaultLedgerId,
    'defaultLedgerSyncId': defaultLedgerSyncId,
    'createdAt': createdAt.toIso8601String(),
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'sources': sources,
    'rows': rows.map((r) => r.toJson()).toList(),
    'proposals': proposals,
    'issues': issues,
    'summary': summary,
    'fingerprint': fingerprint,
    'analysisVersion': analysisVersion,
    'matches': matches,
    'audit': audit,
  };

  factory ReconciliationSession.fromJson(Json j) => ReconciliationSession(
    id: j['id'],
    defaultLedgerId: j['defaultLedgerId'],
    defaultLedgerSyncId: j['defaultLedgerSyncId'],
    createdAt: DateTime.parse(j['createdAt']),
    start: DateTime.parse(j['start']),
    end: DateTime.parse(j['end']),
    accounts: jsonObjects(
      j['accounts'],
    ).map(ReconciliationAccount.fromJson).toList(),
    sources: jsonObjects(j['sources']),
    rows: jsonObjects(j['rows']).map(StatementRow.fromJson).toList(),
    proposals: jsonObjects(j['proposals']),
    issues: List<String>.from(j['issues'] ?? []),
    summary: j['summary'] ?? '',
    fingerprint: j['fingerprint'],
    analysisVersion: j['analysisVersion'] ?? 0,
    matches: jsonObjects(j['matches']),
    audit: j['audit'] == null ? null : jsonObject(j['audit']),
  );
}

int transactionDelta(Json tx, int accountId) {
  final cents = tx['amountCents'] as int;
  if (tx['accountId'] == accountId) {
    return switch (tx['type']) {
      'income' || 'adjustment' => cents,
      'expense' || 'transfer' => -cents,
      _ => 0,
    };
  }
  return tx['type'] == 'transfer' && tx['toAccountId'] == accountId ? cents : 0;
}
