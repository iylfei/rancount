import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/billing/refund_service.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;
  late RefundService refunds;
  late int originalId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    refunds = RefundService(repo);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency, initial_balance) "
        "VALUES (10, 1, '现金', 'CNY', 500)");
    await db.customStatement(
        "INSERT INTO categories (id, name, kind) VALUES (20, '购物', 'expense')");
    originalId = await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      categoryId: 20,
      accountId: 10,
      happenedAt: DateTime(2026, 9, 1),
      currencyCode: 'CNY',
    );
  });

  tearDown(() async => db.close());

  test('multiple partial refunds reduce expense and restore account balance',
      () async {
    final first = await refunds.create(
        originalId: originalId,
        amount: 30,
        accountId: 10,
        happenedAt: DateTime(2026, 9, 2));
    final second = await refunds.create(
        originalId: originalId,
        amount: 70,
        accountId: 10,
        happenedAt: DateTime(2026, 9, 3));

    expect(await refunds.remaining(originalId), 0);
    expect((await repo.getTransactionById(first))!.amount, -30);
    expect((await repo.getTransactionById(second))!.refundOfSyncId,
        (await repo.getTransactionById(originalId))!.syncId);
    expect(await repo.getAccountBalance(10), 500);
    final total = await db
        .customSelect(
            "SELECT SUM(amount) AS expense FROM transactions WHERE type = 'expense'")
        .getSingle();
    expect(total.read<double>('expense'), 0);
  });

  test('over refund is rejected and original cannot be deleted first',
      () async {
    await refunds.create(
        originalId: originalId, amount: 40, happenedAt: DateTime(2026, 9, 2));
    await expectLater(
        refunds.create(
            originalId: originalId,
            amount: 61,
            happenedAt: DateTime(2026, 9, 3)),
        throwsStateError);
    await expectLater(repo.deleteTransaction(originalId), throwsStateError);
    expect(await refunds.remaining(originalId), 60);
  });
}
