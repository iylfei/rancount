import '../../ai/core/bill_info.dart';
import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';

/// Resolve reviewed names exactly once. Confirmation must never use AI fallbacks.
class ConfirmedBillReferences {
  final int? categoryId;
  final Account account;
  final Account? destination;

  const ConfirmedBillReferences(
      this.categoryId, this.account, this.destination);

  static Future<ConfirmedBillReferences> resolve(
      BaseRepository repo, BillInfo bill, int ledgerId) async {
    if (bill.type == null ||
        bill.time == null ||
        bill.amount == null ||
        !bill.amount!.isFinite ||
        bill.amount!.abs() <= 0) {
      throw StateError('请补全交易类型、有效金额和日期');
    }
    final accounts = await repo.getAllAccounts();
    Account account(String? name) {
      final matches = accounts
          .where((a) =>
              a.ledgerId == ledgerId &&
              !a.hidden &&
              a.name.trim() == (name ?? '').trim())
          .toList();
      if (matches.length != 1) {
        throw StateError('资金账户不存在或名称不唯一，请重新选择');
      }
      return matches.single;
    }

    final source = account(
        bill.type == BillType.transfer ? bill.fromAccount : bill.account);
    final currency = bill.currency?.trim().toUpperCase();
    if (currency != null &&
        currency.isNotEmpty &&
        currency != source.currency.toUpperCase()) {
      throw StateError('交易币种与资金账户不一致');
    }
    Account? destination;
    int? categoryId;
    if (bill.type == BillType.transfer) {
      destination = account(bill.toAccount);
      if (source.id == destination.id ||
          source.currency.toUpperCase() != destination.currency.toUpperCase()) {
        throw StateError('转账需要两个不同且币种相同的账户');
      }
    } else {
      final categories = await repo.getAllCategories();
      final matches = categories
          .where((c) =>
              c.kind == bill.type!.name &&
              c.name.trim() == (bill.category ?? '').trim())
          .toList();
      if (matches.length != 1) {
        throw StateError('分类不存在或名称不唯一，请重新选择');
      }
      categoryId = matches.single.id;
    }
    return ConfirmedBillReferences(categoryId, source, destination);
  }
}
