import 'dart:convert';

import 'reconciliation_models.dart';

bool hasReconciliationEvidence(ReconciliationSession s, int accountId) =>
    s.sources.any((source) => source['accountId'] == accountId) ||
    s.rows.any((row) => row.accountId == accountId);

DateTime? earliestReconciliationRecord(
  ReconciliationSession s,
  List<Json> txs,
) {
  final times =
      txs
          .where((t) => t['ledgerId'] == s.defaultLedgerId)
          .map((t) => evidenceTime(t['happenedAt']))
          .whereType<DateTime>()
          .toList()
        ..sort();
  return times.firstOrNull;
}

bool needsReconciliationBaseline(
  ReconciliationSession s,
  List<Json> txs,
  StatementRow row,
) {
  final account = s.accounts.singleWhere((a) => a.id == row.accountId);
  if (account.initialBalanceAt != null || row.time == null) return false;
  final earliest = earliestReconciliationRecord(s, txs);
  // An empty ledger provides no evidence of when its opening balance starts.
  return earliest == null || row.time!.isBefore(earliest);
}

bool reconciliationRowEligible(
  ReconciliationSession s,
  List<Json> txs,
  StatementRow row,
) {
  if (!row.accountConfirmed || row.time == null || row.delta == null) {
    return false;
  }
  final account = s.accounts.singleWhere((a) => a.id == row.accountId);
  return !row.time!.isBefore(s.start) &&
      !row.time!.isAfter(s.end) &&
      !row.time!.isAfter(account.balanceAt) &&
      !(account.initialBalanceAt != null &&
          row.time!.isBefore(account.initialBalanceAt!)) &&
      !needsReconciliationBaseline(s, txs, row);
}

String reconciliationQuestionId(String kind, int accountId, List<String> ids) =>
    '$kind:$accountId:${(ids.toList()..sort()).join(',')}';

String answerEvidenceKey(ReconciliationSession s, Iterable<String> ids) {
  final selected = ids.toSet();
  final rows = s.rows.where((r) => selected.contains(r.id)).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode(rows.map((r) => r.toJson()).toList());
}

List<Json> currentReconciliationAnswers(ReconciliationSession s) =>
    s.answers.where((answer) {
      final ids = List<String>.from(answer['evidenceIds'] ?? []);
      return ids.isNotEmpty &&
          ids.every((id) => s.rows.any((r) => r.id == id)) &&
          answer['evidenceKey'] == answerEvidenceKey(s, ids);
    }).toList();

void addReconciliationQuestion(
  ReconciliationSession s, {
  required String kind,
  required int accountId,
  required String text,
  List<String> evidenceIds = const [],
  String? hint,
}) {
  final id = reconciliationQuestionId(kind, accountId, evidenceIds);
  if (s.questions.any((q) => q['id'] == id)) return;
  s.questions.add({
    'id': id,
    'kind': kind,
    'accountId': accountId,
    'text': text,
    'evidenceIds': evidenceIds,
    'hint': hint,
  });
}
