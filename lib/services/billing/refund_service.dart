import 'package:uuid/uuid.dart';

import '../../data/repositories/local/local_repository.dart';

/// A refund is a negative expense on its own date. This preserves account and
/// category arithmetic, while the original sync ID records its provenance.
class RefundService {
  final LocalRepository repository;

  const RefundService(this.repository);

  Future<double> remaining(int originalId) async {
    final db = repository.db;
    final original = await (db.select(db.transactions)
          ..where((t) => t.id.equals(originalId)))
        .getSingleOrNull();
    if (original == null ||
        original.type != 'expense' ||
        original.amount <= 0 ||
        original.syncId == null ||
        original.refundOfSyncId != null) {
      throw StateError('Only an original expense can be refunded');
    }
    final refunds = await (db.select(db.transactions)
          ..where((t) => t.refundOfSyncId.equals(original.syncId!)))
        .get();
    final refunded = refunds.fold<double>(0, (sum, tx) => sum - tx.amount);
    return (original.amount - refunded).clamp(0, original.amount).toDouble();
  }

  Future<int> create({
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
          original.amount <= 0 ||
          original.syncId == null ||
          original.refundOfSyncId != null) {
        throw StateError('Only an original expense can be refunded');
      }
      final remainingAmount = await remaining(originalId);
      if (amount > remainingAmount + 0.005) {
        throw StateError('Refund exceeds the original expense');
      }
      final targetAccountId = accountId;
      if (targetAccountId != null) {
        final target = await repository.getAccount(targetAccountId);
        if (target == null ||
            target.ledgerId != original.ledgerId ||
            target.currency.toUpperCase() !=
                (original.currencyCode ?? target.currency).toUpperCase()) {
          throw StateError('Refund account must use the expense currency');
        }
      }
      final nativeAmount = original.nativeAmount == null
          ? null
          : -amount * original.nativeAmount! / original.amount;
      return repository.addTransaction(
        ledgerId: original.ledgerId,
        type: 'expense',
        amount: -amount,
        categoryId: original.categoryId,
        accountId: targetAccountId,
        happenedAt: happenedAt,
        note: note ?? '退款',
        syncId: const Uuid().v4(),
        refundOfSyncId: original.syncId,
        merchant: original.merchant,
        itemDescription: original.itemDescription,
        paymentChannel: original.paymentChannel,
        currencyCode: original.currencyCode,
        nativeAmount: nativeAmount,
      );
    });
  }
}
