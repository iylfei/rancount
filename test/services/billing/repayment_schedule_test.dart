import 'dart:io';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/entity_serializer.dart';
import 'package:beecount/cloud/transactions_json.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/external_write_refresh.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/billing/repayment_schedule.dart';
import 'package:beecount/services/billing/repayment_service.dart';
import 'package:beecount/utils/beijing_time.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  d.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'JSON backup restores a repayment-only account with its cross-year plans',
    () async {
      final source = BeeDatabase.forTesting(NativeDatabase.memory());
      final target = BeeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await source.close();
        await target.close();
      });
      final sourceRepo = LocalRepository(source);
      final targetRepo = LocalRepository(target);
      final ledger = await sourceRepo.createLedger(
        name: 'source',
        currency: 'CNY',
      );
      final targetLedger = await targetRepo.createLedger(
        name: 'target',
        currency: 'CNY',
      );
      final accountId = await sourceRepo.createAccount(
        ledgerId: ledger,
        name: 'loan',
        type: 'loan',
        currency: 'CNY',
      );
      await editRepaymentSchedule(
        sourceRepo,
        accountId,
        (s) => s.assign([DateTime(2026, 12), DateTime(2027, 1)], 123.45),
      );
      final json = await exportTransactionsJson(source, ledger);
      await importTransactionsJson(targetRepo, targetLedger, json);
      final restored = (await targetRepo.getAllAccounts()).single;
      expect(RepaymentSchedule.decode(restored.repaymentSchedule).plans.keys, [
        '2026-12',
        '2027-01',
      ]);
    },
  );
  test(
    'assigns arbitrary and continuous months across years and preserves paid state',
    () {
      final months = repaymentMonthRange(DateTime(2026, 11), DateTime(2027, 2));
      var schedule = RepaymentSchedule().assign(months, 123.45);
      expect(schedule.plans.keys, ['2026-11', '2026-12', '2027-01', '2027-02']);
      schedule = schedule.markPaid(DateTime(2026, 12), true).assign([
        DateTime(2026, 12),
        DateTime(2027, 3),
      ], 88.88);
      final restored = RepaymentSchedule.decode(schedule.encode());
      expect(restored.plans['2026-12']!.amountMinor, 8888);
      expect(restored.plans['2026-12']!.markedPaid, isTrue);
      expect(restored.plans['2027-01']!.amountMinor, 12345);
      expect(
        restored.remove(DateTime(2027, 1)).plans.containsKey('2027-01'),
        isFalse,
      );
      expect(
        () => repaymentMonthRange(DateTime(2027, 1), DateTime(2026, 12)),
        throwsFormatException,
      );
      expect(
        () => RepaymentSchedule().assign(months, double.nan),
        throwsFormatException,
      );
      expect(
        () => RepaymentSchedule.decode('{"version":1,"months":{"2026-13":{}}}'),
        throwsFormatException,
      );
    },
  );

  test(
    'counts native-currency incoming repayments within Beijing calendar months',
    () async {
      final db = BeeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalRepository(db, changeTracker: ChangeTracker(db));
      final ledger = await repo.createLedger(name: 'test', currency: 'CNY');
      final card = await repo.createAccount(
        ledgerId: ledger,
        name: 'card',
        type: 'credit_card',
        currency: 'CNY',
      );
      final bank = await repo.createAccount(
        ledgerId: ledger,
        name: 'bank',
        type: 'bank_card',
        currency: 'CNY',
      );
      await editRepaymentSchedule(
        repo,
        card,
        (s) => s.assign([DateTime(2027, 1)], 100),
      );
      final account = (await repo.getAccount(card))!;
      expect(
        EntitySerializer.serializeAccount(account)['repaymentSchedule'],
        account.repaymentSchedule,
      );
      final recorded =
          await (db.select(db.localChanges)..where(
                (t) => t.entityType.equals('account') & t.entityId.equals(card),
              ))
              .get();
      expect(recorded, isNotEmpty);
      Future<int> transfer(
        double amount,
        DateTime date, {
        String currency = 'CNY',
        int? destination,
      }) => repo.addTransaction(
        ledgerId: ledger,
        type: 'transfer',
        amount: amount,
        accountId: bank,
        toAccountId: destination ?? card,
        happenedAt: date,
        currencyCode: currency,
      );
      // 16:00 UTC is midnight on Jan 1 in Beijing.
      final paid = await transfer(40, DateTime.utc(2026, 12, 31, 16));
      await transfer(10, DateTime.utc(2026, 12, 31, 15, 59));
      await transfer(20, beijingDate(2027, 2));
      await transfer(1000, beijingDate(2027, 1, 5), currency: 'USD');
      await transfer(1000, beijingDate(2027, 1, 5), destination: bank);
      await repo.addTransaction(
        ledgerId: ledger,
        type: 'income',
        amount: 1000,
        accountId: card,
        happenedAt: beijingDate(2027, 1, 6),
      );
      Future<MonthlyRepayment> read() async =>
          (await watchMonthlyRepayments(db, DateTime(2027, 1)).first).single;
      expect((await read()).remaining, 60);
      await editRepaymentSchedule(
        repo,
        card,
        (s) => s.markPaid(DateTime(2027, 1), true),
      );
      expect((await read()).remaining, 0);
      await editRepaymentSchedule(
        repo,
        card,
        (s) => s.markPaid(DateTime(2027, 1), false),
      );
      expect((await read()).remaining, 60);
      await repo.deleteTransaction(paid);
      expect((await read()).remaining, 100);
      await transfer(200, beijingDate(2027, 1, 15));
      expect((await read()).remaining, 0);
      expect((await read()).paid, 100);
    },
  );

  test(
    'external write notification refreshes the existing transaction subscription',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rancount-repay-',
      );
      final file = File('${directory.path}/db.sqlite');
      final mainDb = BeeDatabase.forTesting(NativeDatabase(file));
      final otherDb = BeeDatabase.forTesting(NativeDatabase(file));
      addTearDown(() async {
        await mainDb.close();
        await otherDb.close();
        await directory.delete(recursive: true);
      });
      final mainRepo = LocalRepository(mainDb);
      final otherRepo = LocalRepository(otherDb);
      final ledger = await mainRepo.createLedger(name: 'test', currency: 'CNY');
      final updates = <List<Transaction>>[];
      final sub = mainRepo
          .watchRecentTransactions(ledgerId: ledger)
          .listen(updates.add);
      addTearDown(sub.cancel);
      await mainRepo.watchRecentTransactions(ledgerId: ledger).first;
      final next = mainRepo
          .watchRecentTransactions(ledgerId: ledger)
          .firstWhere((rows) => rows.isNotEmpty);
      await otherRepo.addTransaction(
        ledgerId: ledger,
        type: 'expense',
        amount: 12,
        happenedAt: beijingDate(2026, 10, 7),
      );
      refreshExternalDatabaseWrites(mainDb);
      expect(
        (await next.timeout(const Duration(seconds: 5))).single.amount,
        12,
      );
    },
  );

  test(
    'v35 upgrade adds the nullable repayment column without changing balances',
    () async {
      final dir = await Directory.systemTemp.createTemp('rancount-v35-');
      final file = File('${dir.path}/db.sqlite');
      final initial = BeeDatabase.forTesting(NativeDatabase(file));
      final repo = LocalRepository(initial);
      final ledger = await repo.createLedger(name: 'legacy', currency: 'CNY');
      final id = await repo.createAccount(
        ledgerId: ledger,
        name: 'legacy card',
        type: 'credit_card',
        currency: 'CNY',
        initialBalance: -321,
      );
      await initial.customStatement(
        'ALTER TABLE accounts DROP COLUMN repayment_schedule',
      );
      await initial.customStatement('PRAGMA user_version = 35');
      await initial.close();
      final upgraded = BeeDatabase.forTesting(NativeDatabase(file));
      try {
        final account = await (upgraded.select(
          upgraded.accounts,
        )..where((a) => a.id.equals(id))).getSingle();
        expect(account.initialBalance, -321);
        expect(account.repaymentSchedule, isNull);
      } finally {
        await upgraded.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
