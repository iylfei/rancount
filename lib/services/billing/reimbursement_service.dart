import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';

class ReimbursementItem {
  final Transaction original;
  final Category? category;
  final Account? account;
  final List<Transaction> reimbursements;
  final double reimbursedAmount;
  final double remainingAmount;
  final double remainingNativeAmount;

  const ReimbursementItem({
    required this.original,
    this.category,
    this.account,
    required this.reimbursements,
    required this.reimbursedAmount,
    required this.remainingAmount,
    required this.remainingNativeAmount,
  });

  bool get isSettled => remainingAmount <= 0.005;
  bool get isPartial => reimbursedAmount > 0.005 && !isSettled;
}

class ReimbursementSummary {
  final List<ReimbursementItem> items;
  final double totalPendingNative;
  final double totalReimbursedNative;
  final int pendingCount;
  final int settledCount;

  const ReimbursementSummary({
    required this.items,
    required this.totalPendingNative,
    required this.totalReimbursedNative,
    required this.pendingCount,
    required this.settledCount,
  });
}

/// Manages reimbursable expenses independently of real income/expense stats.
///
/// - A reimbursable expense (`isReimbursable = true`, `excludeFromStats = true`,
///   `excludeFromBudget = true`) still deducts from its payment account balance
///   without inflating real expense or budget usage.
/// - A reimbursement payout (`type = 'income'`, `reimburseOfSyncId = original.syncId`,
///   `excludeFromStats = true`, `excludeFromBudget = true`) credits the receiving
///   account balance without inflating real income.
class ReimbursementService {
  final LocalRepository repository;

  const ReimbursementService(this.repository);

  Future<ReimbursementSummary> loadSummary(int ledgerId) async {
    final db = repository.db;
    final originals = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals('expense') &
              t.isReimbursable.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.happenedAt)]))
        .get();

    if (originals.isEmpty) {
      return const ReimbursementSummary(
        items: [],
        totalPendingNative: 0,
        totalReimbursedNative: 0,
        pendingCount: 0,
        settledCount: 0,
      );
    }

    final syncIds = originals
        .map((t) => t.syncId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();

    final payouts = syncIds.isEmpty
        ? <Transaction>[]
        : await (db.select(db.transactions)
              ..where((t) => t.reimburseOfSyncId.isIn(syncIds))
              ..orderBy([(t) => OrderingTerm.desc(t.happenedAt)]))
            .get();

    final payoutsByOrigin = <String, List<Transaction>>{};
    for (final p in payouts) {
      final key = p.reimburseOfSyncId;
      if (key != null) {
        payoutsByOrigin.putIfAbsent(key, () => []).add(p);
      }
    }

    final categories = {
      for (final c in await repository.getAllCategories()) c.id: c,
    };
    final accounts = {
      for (final a in await repository.getAllAccounts()) a.id: a,
    };

    final items = <ReimbursementItem>[];
    var totalPendingNative = 0.0;
    var totalReimbursedNative = 0.0;
    var pendingCount = 0;
    var settledCount = 0;

    for (final tx in originals) {
      final linked = tx.syncId != null
          ? (payoutsByOrigin[tx.syncId!] ?? const <Transaction>[])
          : const <Transaction>[];
      final reimbursed = linked.fold<double>(0, (s, p) => s + p.amount.abs());
      final origAbs = tx.amount.abs();
      final remaining = (origAbs - reimbursed).clamp(0.0, origAbs).toDouble();

      final origNative = (tx.nativeAmount ?? tx.amount).abs();
      final reimbursedNative = linked.fold<double>(
        0,
        (s, p) => s + (p.nativeAmount ?? p.amount).abs(),
      );
      final remainingNative =
          (origNative - reimbursedNative).clamp(0.0, origNative).toDouble();

      final item = ReimbursementItem(
        original: tx,
        category: tx.categoryId != null ? categories[tx.categoryId!] : null,
        account: tx.accountId != null ? accounts[tx.accountId!] : null,
        reimbursements: linked,
        reimbursedAmount: reimbursed,
        remainingAmount: remaining,
        remainingNativeAmount: remainingNative,
      );
      items.add(item);

      totalReimbursedNative += reimbursedNative;
      if (item.isSettled) {
        settledCount++;
      } else {
        pendingCount++;
        totalPendingNative += remainingNative;
      }
    }

    return ReimbursementSummary(
      items: items,
      totalPendingNative: totalPendingNative,
      totalReimbursedNative: totalReimbursedNative,
      pendingCount: pendingCount,
      settledCount: settledCount,
    );
  }

  Future<double> remaining(int originalId) async {
    final db = repository.db;
    final original = await (db.select(db.transactions)
          ..where((t) => t.id.equals(originalId)))
        .getSingleOrNull();
    if (original == null ||
        original.type != 'expense' ||
        !original.isReimbursable ||
        original.amount <= 0 ||
        original.syncId == null) {
      throw StateError('Only a reimbursable expense can be reimbursed');
    }
    final payouts = await (db.select(db.transactions)
          ..where((t) => t.reimburseOfSyncId.equals(original.syncId!)))
        .get();
    final reimbursed = payouts.fold<double>(0, (s, p) => s + p.amount.abs());
    return (original.amount - reimbursed)
        .clamp(0.0, original.amount)
        .toDouble();
  }

  /// Record a full or partial reimbursement payout.
  /// Credits [accountId] while excluding the payout from real income statistics.
  Future<int> reimburse({
    required int originalId,
    required double amount,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError.value(amount);
    final db = repository.db;
    return db.transaction(() async {
      final original = await (db.select(db.transactions)
            ..where((t) => t.id.equals(originalId)))
          .getSingleOrNull();
      if (original == null ||
          original.type != 'expense' ||
          !original.isReimbursable ||
          original.amount <= 0 ||
          original.syncId == null) {
        throw StateError('Only a reimbursable expense can be reimbursed');
      }
      final rem = await remaining(originalId);
      if (amount > rem + 0.005) {
        throw StateError('Reimbursement exceeds remaining pending amount');
      }
      if (accountId != null) {
        final target = await repository.getAccount(accountId);
        if (target == null ||
            target.ledgerId != original.ledgerId ||
            target.currency.toUpperCase() !=
                (original.currencyCode ?? target.currency).toUpperCase()) {
          throw StateError('Reimbursement account must match expense currency');
        }
      }
      final nativeAmount = original.nativeAmount == null
          ? null
          : amount * original.nativeAmount!.abs() / original.amount.abs();
      final effectiveNote = (note != null && note.trim().isNotEmpty)
          ? note.trim()
          : (original.note != null && original.note!.trim().isNotEmpty
              ? '报销到账 · ${original.note!.trim()}'
              : '报销到账');
      return repository.addTransaction(
        ledgerId: original.ledgerId,
        type: 'income',
        amount: amount,
        accountId: accountId,
        happenedAt: happenedAt,
        note: effectiveNote,
        syncId: const Uuid().v4(),
        reimburseOfSyncId: original.syncId,
        excludeFromStats: true,
        excludeFromBudget: true,
        currencyCode: original.currencyCode,
        nativeAmount: nativeAmount,
      );
    });
  }
}
