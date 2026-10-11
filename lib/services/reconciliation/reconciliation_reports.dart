import 'reconciliation_evidence.dart';
import 'reconciliation_models.dart';

class AccountReconciliationReport {
  final ReconciliationAccount account;
  final int bookBalance;
  final int? actualBalance;
  final int projectedBalance;
  final int? openingDifference;
  final int? periodDifference;
  final List<String> warnings;
  final bool coverageConfirmed;
  final bool hasEvidence;
  final bool evidenceReady;
  final int pendingRows;
  final int pendingRecords;
  final DateTime periodStart;
  AccountReconciliationReport({
    required this.account,
    required this.bookBalance,
    required this.actualBalance,
    required this.projectedBalance,
    this.openingDifference,
    this.periodDifference,
    required this.warnings,
    required this.coverageConfirmed,
    required this.hasEvidence,
    required this.evidenceReady,
    required this.pendingRows,
    required this.pendingRecords,
    required this.periodStart,
  });

  int? get remainingDifference =>
      actualBalance == null ? null : actualBalance! - projectedBalance;

  String get status {
    if (actualBalance == null) {
      return account.isLiability ? '还缺实际总欠款' : '还缺实际余额';
    }
    if (!hasEvidence) return '按未上传默认无变动，尚未验证流水';
    if (!coverageConfirmed) return '尚未确认完整流水范围';
    if (!evidenceReady) return '资料仍需确认，暂不能判断差额来源';
    if (remainingDifference == 0) {
      return pendingRows == 0 && pendingRecords == 0
          ? '已对齐'
          : '余额已一致，仍有收付记录待核对';
    }
    if (openingDifference != null && openingDifference != 0) {
      if (remainingDifference != openingDifference) {
        return '仍有期间和期初差额，需要分别补充证据';
      }
      return '仍有期初差额，需要更早的证据';
    }
    if (account.initialBalanceAt == null && periodDifference == 0) {
      return '请确认初始余额对应日期与金额';
    }
    return '期间差额尚未解决，请补充流水或确认用途';
  }
}

List<AccountReconciliationReport> reconciliationReports(
  ReconciliationSession session,
  List<Json> transactions,
  Map<int, int> initialBalances, {
  List<Json>? proposals,
}) {
  final projected = {for (final t in transactions) '${t['id']}': t};
  for (final p
      in proposals ?? session.proposals.where((p) => p['selected'] == true)) {
    for (final m in jsonObjects(p['mutations'])) {
      final beforeId = m['transactionId'];
      if (beforeId != null) projected.remove('$beforeId');
      if (m['after'] != null) {
        projected['new:${m['id']}'] = jsonObject(m['after']);
      }
    }
  }
  final reports = <AccountReconciliationReport>[];
  for (final a in session.accounts) {
    final until = a.balanceAt.isBefore(session.end) ? a.balanceAt : session.end;
    final periodStart =
        a.initialBalanceAt != null && a.initialBalanceAt!.isAfter(session.start)
        ? a.initialBalanceAt!
        : session.start;
    final hasEvidence = hasReconciliationEvidence(session, a.id);
    final coverageConfirmed = hasEvidence && a.covers(periodStart, until);
    final rows =
        session.rows
            .where(
              (r) =>
                  r.accountId == a.id &&
                  r.time != null &&
                  r.delta != null &&
                  r.accountConfirmed &&
                  !r.time!.isBefore(periodStart) &&
                  !r.time!.isAfter(until),
            )
            .toList()
          ..sort((a, b) => a.time!.compareTo(b.time!));
    int balance(Iterable<Json> txs, DateTime at, {bool inclusive = true}) =>
        (initialBalances[a.id] ?? 0) +
        txs
            .where((t) {
              final time = DateTime.parse(t['happenedAt']);
              return inclusive ? !time.isAfter(at) : time.isBefore(at);
            })
            .fold<int>(0, (sum, t) => sum + transactionDelta(t, a.id));
    final book = balance(transactions, until);
    final warnings = <String>[];
    final badRows = session.rows
        .where(
          (r) => r.accountId == a.id && (r.time == null || r.delta == null),
        )
        .length;
    if (badRows > 0) warnings.add('$badRows 条流水缺少有效时间或金额');
    if (!a.complete) warnings.add('流水资料仍有未识别或待确认内容，暂不能计算完整期间差额');
    if (hasEvidence && !coverageConfirmed) {
      warnings.add('识别成功不代表流水完整，请确认已覆盖核对期间的全部流水');
    }
    if (!hasEvidence) warnings.add('未上传流水按无变动处理；此假设不能证明期间完整或差额来自历史');
    final uncertain = session.rows
        .where(
          (r) =>
              r.accountId == a.id &&
              r.time != null &&
              !r.time!.isBefore(periodStart) &&
              !r.time!.isAfter(until) &&
              (!r.accountConfirmed ||
                  needsReconciliationBaseline(session, transactions, r)),
        )
        .length;
    if (uncertain > 0) warnings.add('$uncertain 条流水的资金账户或初始余额日期仍待确认');
    var gap = false;
    for (var i = 1; i < rows.length; i++) {
      final previous = rows[i - 1];
      final current = rows[i];
      if (previous.balanceAfter != null &&
          current.balanceAfter != null &&
          previous.balanceAfter! + current.delta! != current.balanceAfter) {
        gap = true;
        warnings.add('余额不连续：${current.description}，请检查缺页、顺序或识别值');
      }
    }
    final actual =
        a.actualBalance ??
        (a.complete &&
                coverageConfirmed &&
                !gap &&
                badRows == 0 &&
                uncertain == 0 &&
                rows.isNotEmpty
            ? rows.last.balanceAfter
            : null);
    final externalNet = rows.fold<int>(0, (sum, r) => sum + r.delta!);
    final bookOpening = balance(transactions, periodStart, inclusive: false);
    final periodDifference =
        a.complete &&
            coverageConfirmed &&
            badRows == 0 &&
            uncertain == 0 &&
            !gap
        ? externalNet - (book - bookOpening)
        : null;
    if (actual != null &&
        rows.isNotEmpty &&
        rows.last.balanceAfter != null &&
        a.complete &&
        coverageConfirmed &&
        actual != rows.last.balanceAfter) {
      warnings.add('填写余额与最后一笔交易后余额不同，请检查余额时点或遗漏流水');
      gap = true;
    }
    final selectedProposals = session.applied
        ? session.proposals.where((p) => p['selected'] == true)
        : proposals ?? session.proposals.where((p) => p['selected'] == true);
    final coveredIds = {
      for (final match in session.matches) match['evidenceId'],
      for (final p in selectedProposals)
        ...List<String>.from(p['evidenceIds'] ?? []),
    };
    final coveredRecords = {
      for (final match in session.matches.where((m) => m['accountId'] == a.id))
        match['transactionId'],
      for (final p in selectedProposals)
        for (final m in jsonObjects(p['mutations']))
          if (m['transactionId'] != null) m['transactionId'],
      if (session.applied)
        for (final change in jsonObjects(session.audit?['changes'])) ...[
          if (change['before'] != null) jsonObject(change['before'])['id'],
          if (change['after'] != null) jsonObject(change['after'])['id'],
        ],
    };
    final pendingRecords = transactions.where((t) {
      final time = evidenceTime(t['happenedAt'])!;
      return t['type'] != 'adjustment' &&
          transactionDelta(t, a.id) != 0 &&
          !time.isBefore(periodStart) &&
          !time.isAfter(until) &&
          !coveredRecords.contains(t['id']);
    }).length;
    reports.add(
      AccountReconciliationReport(
        account: a,
        bookBalance: book,
        actualBalance: actual,
        projectedBalance: balance(projected.values, until),
        periodDifference: gap ? null : periodDifference,
        openingDifference:
            actual == null ||
                periodDifference == null ||
                gap ||
                a.initialBalanceAt == null
            ? null
            : actual - book - periodDifference,
        warnings: warnings,
        coverageConfirmed: coverageConfirmed,
        hasEvidence: hasEvidence,
        evidenceReady: a.complete && badRows == 0 && uncertain == 0 && !gap,
        pendingRows: rows.where((r) => !coveredIds.contains(r.id)).length,
        pendingRecords: pendingRecords,
        periodStart: periodStart,
      ),
    );
  }
  return reports;
}
