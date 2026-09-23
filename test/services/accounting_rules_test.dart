import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('credit expense, repayment, adjustment and edits keep balances correct',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    final repo = LocalRepository(db);
    try {
      final ledger = await repo.createLedger(name: '日常');
      final cash = await repo.createAccount(
          ledgerId: ledger, name: '储蓄卡', type: 'bank', initialBalance: 200);
      final card = await repo.createAccount(
          ledgerId: ledger, name: '信用卡', type: 'credit_card');
      final date = DateTime(2026, 9, 23, 12);

      final expense = await repo.addTransaction(
          ledgerId: ledger,
          type: 'expense',
          amount: 80,
          accountId: card,
          happenedAt: date);
      expect(await repo.getAccountBalance(card), -80);
      expect(await repo.getCreditCardUsedAmount(card), 80);

      final repayment = await repo.addTransaction(
          ledgerId: ledger,
          type: 'transfer',
          amount: 50,
          accountId: cash,
          toAccountId: card,
          happenedAt: date);
      expect(await repo.getAccountBalance(cash), 150);
      expect(await repo.getAccountBalance(card), -30);
      expect((await repo.monthlyTotals(ledgerId: ledger, month: date)).$2, 80);

      await repo.createAdjustmentTransaction(
          ledgerId: ledger, accountId: cash, amount: 20, happenedAt: date);
      expect(await repo.getAccountBalance(cash), 170);
      expect((await repo.monthlyTotals(ledgerId: ledger, month: date)).$2, 80);

      await repo.updateTransaction(id: expense, type: 'expense', amount: 60);
      expect(await repo.getAccountBalance(card), -10);
      expect((await repo.monthlyTotals(ledgerId: ledger, month: date)).$2, 60);
      await repo.deleteTransaction(repayment);
      expect(await repo.getAccountBalance(cash), 220);
      expect(await repo.getAccountBalance(card), -60);
      await repo.deleteTransaction(expense);
      expect(await repo.getAccountBalance(card), 0);
      expect((await repo.monthlyTotals(ledgerId: ledger, month: date)).$2, 0);
    } finally {
      await db.close();
    }
  });
}
