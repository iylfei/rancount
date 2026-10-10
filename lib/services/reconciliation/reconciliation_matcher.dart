import '../../utils/beijing_time.dart';
import 'reconciliation_models.dart';

/// Match account movements, including both legs of a transfer. Amount alone
/// never establishes a match, and one recorded leg cannot cover two rows.
class ReconciliationMatcher {
  final List<StatementRow> rows;
  final List<Json> transactions;
  final Map<String, Json> confirmed = {};
  final Map<String, List<Json>> _candidates = {};

  ReconciliationMatcher(this.rows, this.transactions) {
    final strong = <String, List<Json>>{};
    final claims = <String, List<String>>{};
    for (final row in rows) {
      strong[row.id] = compatible(row).where((t) {
        // Transfers and refunds recorded as income still need semantic review.
        if (t['type'] == 'transfer' ||
            (t['type'] == 'income' &&
                RegExp('退款|退货|退票').hasMatch(row.description))) {
          return false;
        }
        return _gap(row, t) <= const Duration(seconds: 90) || _hasOrder(row, t);
      }).toList();
      for (final t in strong[row.id]!) {
        claims.putIfAbsent('${t['id']}:${row.accountId}', () => []).add(row.id);
      }
    }
    for (final row in rows) {
      final candidates = strong[row.id]!;
      if (candidates.length == 1 &&
          claims['${candidates.single['id']}:${row.accountId}']!.length == 1) {
        confirmed[row.id] = candidates.single;
      }
    }
  }

  Duration _gap(StatementRow row, Json t) =>
      evidenceTime(t['happenedAt'])!.difference(row.time!).abs();

  bool _hasOrder(StatementRow row, Json t) {
    final order = row.orderId;
    return order != null &&
        order.length >= 8 &&
        !order.contains('…') &&
        !order.contains('...') &&
        _details(t).contains(order);
  }

  List<Json> candidates(StatementRow row) =>
      _candidates.putIfAbsent(row.id, () {
        final result = transactions.where((t) {
          if (t['type'] == 'adjustment') return false;
          final time = evidenceTime(t['happenedAt']);
          if (time == null) return false;
          final gap = time.difference(row.time!).abs();
          return gap <= const Duration(days: 3) &&
              ((t['amountCents'] as int).abs() == row.delta!.abs() ||
                  (gap <= const Duration(hours: 48) &&
                      (t['accountId'] == row.accountId ||
                          t['toAccountId'] == row.accountId)));
        }).toList();
        result.sort((a, b) => _gap(row, a).compareTo(_gap(row, b)));
        return result;
      });

  List<Json> compatible(StatementRow row, {bool unclaimedOnly = false}) =>
      candidates(row).where((t) {
        if (transactionDelta(t, row.accountId) != row.delta ||
            _gap(row, t) > const Duration(hours: 48) ||
            _conflictingDetails(row, t)) {
          return false;
        }
        return !unclaimedOnly ||
            !rows.any(
              (other) =>
                  other.id != row.id &&
                  other.accountId == row.accountId &&
                  confirmed[other.id]?['id'] == t['id'],
            );
      }).toList();

  bool _conflictingDetails(StatementRow row, Json t) {
    final merchant = t['merchant']?.toString().trim() ?? '';
    if (merchant.isNotEmpty &&
        row.description.isNotEmpty &&
        !row.description.contains(merchant)) {
      return true;
    }
    final order = row.orderId;
    final recordedOrders = _orders(_details(t));
    return order != null &&
        !order.contains('…') &&
        !order.contains('...') &&
        recordedOrders.isNotEmpty &&
        !recordedOrders.contains(order);
  }

  Json comparison(StatementRow row) => {
    'evidenceId': row.id,
    'confirmedTransactionId': confirmed[row.id]?['id'],
    'candidateTransactionIds': candidates(row).map((t) => t['id']).toList(),
    'sameAccountAndDirectionIds': compatible(
      row,
      unclaimedOnly: true,
    ).map((t) => t['id']).toList(),
  };

  /// A same-account, same-direction record within two days is a possible date
  /// correction, not proven missing income/expense. Keep it out of additions
  /// until the ambiguity is resolved; other days remain model candidates.
  void checkAdditions(List<Json> mutations, Iterable<StatementRow> evidence) {
    final replaced = mutations
        .map((m) => m['transactionId'])
        .whereType<int>()
        .toSet();
    for (final m in mutations) {
      if (m['transactionId'] != null || m['after'] == null) continue;
      final after = jsonObject(m['after']);
      var anchored = false;
      for (final row in evidence) {
        if (transactionDelta(after, row.accountId) != row.delta ||
            evidenceTime(after['happenedAt'])!.difference(row.time!).abs() >
                const Duration(seconds: 90)) {
          continue;
        }
        anchored = true;
        final existing = compatible(
          row,
          unclaimedOnly: true,
        ).where((t) => !replaced.contains(t['id'])).toList();
        if (existing.isNotEmpty) {
          throw StateError(
            '${moneyText(row.delta!.abs())} 的流水已有同账户、同方向候选 '
            '${existing.map((t) => '#${t['id']}（${beijingTime(evidenceTime(t['happenedAt'])!).toIso8601String()}）').join('、')}。'
            '请先核对是否同一笔或修正原记录，未纳入新增建议。',
          );
        }
      }
      if (!anchored) {
        throw StateError('新增建议的账户、金额、方向或时间与引用流水不符，请先核对原图');
      }
    }
    assertNoDuplicateAdditions(mutations, transactions);
  }
}

/// Models sometimes return a bulk list of independent additions. Validate
/// those separately, so one existing transaction does not discard unrelated
/// real omissions. Refund dependencies and replacements remain atomic.
Iterable<Json> independentReconciliationProposals(
  Json proposal,
  Map<String, StatementRow> evidence,
) sync* {
  final mutations = jsonObjects(proposal['mutations']);
  final ids = List<String>.from(proposal['evidenceIds'] ?? []);
  if (mutations.length < 2 ||
      mutations.any(
        (m) =>
            m['transactionId'] != null ||
            m['after'] == null ||
            jsonObject(m['after'])['refundOfMutationId'] != null,
      )) {
    yield proposal;
    return;
  }
  final parts = <Json>[];
  for (final m in mutations) {
    final after = jsonObject(m['after']);
    final time = evidenceTime(after['happenedAt']);
    if (time == null || after['amountCents'] is! int) {
      yield proposal;
      return;
    }
    final related = ids.where((id) {
      final row = evidence[id];
      return row != null &&
          transactionDelta(after, row.accountId) == row.delta &&
          time.difference(row.time!).abs() <= const Duration(seconds: 90);
    }).toList();
    if (related.isEmpty) {
      yield proposal;
      return;
    }
    final names = related
        .map((id) => evidence[id]!.description)
        .toSet()
        .join('、');
    final type = after['type'] == 'transfer'
        ? '转账'
        : transactionDelta(after, evidence[related.first]!.accountId) < 0
        ? '支出'
        : '入账';
    parts.add({
      ...proposal,
      'title': '核对$type ${moneyText((after['amountCents'] as int).abs())}',
      'reason': '流水显示：$names。请核对这笔记录及下方修改内容。',
      'evidenceIds': related,
      'mutations': [m],
    });
  }
  yield* parts;
}

String _details(Json t) => [
  t['note'],
  t['merchant'],
  t['itemDescription'],
  t['orderId'],
].whereType<String>().join(' ');

Set<String> _orders(String details) => RegExp(
  r'(?:订单(?:编号|号)?|商户单号|交易(?:编号|号)?)\s*[:：]?\s*([A-Za-z0-9-]{8,})',
).allMatches(details).map((m) => m[1]!).toSet();

/// Also runs at the accounting boundary, so edited and legacy AI proposals
/// cannot bypass the duplicate check. Evaluate the final plan, allowing a
/// transfer to be replaced by its corrected expense/income pair.
void assertNoDuplicateAdditions(List<Json> mutations, List<Json> transactions) {
  final replaced = mutations
      .map((m) => m['transactionId'])
      .whereType<int>()
      .toSet();
  final projected = transactions
      .where((t) => !replaced.contains(t['id']))
      .toList();
  projected.addAll(
    mutations
        .where((m) => m['transactionId'] != null && m['after'] != null)
        .map((m) => jsonObject(m['after'])),
  );
  for (final m in mutations) {
    if (m['transactionId'] != null || m['after'] == null) continue;
    final after = jsonObject(m['after']);
    final time = evidenceTime(after['happenedAt']);
    if (time == null || after['amountCents'] is! int) continue;
    for (final other in projected) {
      if (other['type'] == 'adjustment') continue;
      final otherTime = evidenceTime(other['happenedAt']);
      if (otherTime == null ||
          time.difference(otherTime).abs() > const Duration(seconds: 90)) {
        continue;
      }
      final orders = _orders(_details(after));
      final otherOrders = _orders(_details(other));
      if (orders.isNotEmpty &&
          otherOrders.isNotEmpty &&
          orders.intersection(otherOrders).isEmpty) {
        continue;
      }
      final merchant = after['merchant']?.toString().trim() ?? '';
      final otherMerchant = other['merchant']?.toString().trim() ?? '';
      if (merchant.isNotEmpty &&
          otherMerchant.isNotEmpty &&
          merchant != otherMerchant) {
        continue;
      }
      for (final accountId in [
        after['accountId'],
        if (after['type'] == 'transfer') after['toAccountId'],
      ].whereType<int>()) {
        final delta = transactionDelta(after, accountId);
        if (delta != 0 && delta == transactionDelta(other, accountId)) {
          throw StateError(
            '新增建议与已有${other['id'] == null ? '计划' : '记录 #${other['id']}'}'
            '的账户、金额、方向和时间重叠，请核对或修正原记录，避免重复补记',
          );
        }
      }
    }
    projected.add(after);
  }
}
