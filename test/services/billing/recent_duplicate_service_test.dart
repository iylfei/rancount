import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/billing/recent_duplicate_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repository;

  group('新账单重复判断', () {
    setUp(() {
      db = BeeDatabase.forTesting(NativeDatabase.memory());
      repository = LocalRepository(db);
    });

    tearDown(() async => db.close());

    test('24 小时内只按金额提醒，不限制账本、类型或币种', () async {
      await repository.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 35,
        happenedAt: DateTime(2020, 1, 1),
        currencyCode: 'CNY',
      );
      await repository.addTransaction(
        ledgerId: 2,
        type: 'income',
        amount: 36,
        happenedAt: DateTime.now(),
        currencyCode: 'USD',
      );

      for (final amount in [35.0, 36.0]) {
        expect(
          await RecentDuplicateService.exists(
            repository: repository,
            amount: amount,
          ),
          isTrue,
        );
      }
      expect(
        await RecentDuplicateService.exists(repository: repository, amount: 37),
        isFalse,
      );
    });

    test('超过 24 小时或账单已删除，不再命中', () async {
      final id = await repository.addTransaction(
        ledgerId: 1,
        type: 'expense',
        amount: 35,
        happenedAt: DateTime.now(),
      );
      await db.customStatement(
        'UPDATE recent_transaction_records SET recorded_at = ? WHERE transaction_id = ?',
        [
          DateTime.now()
                  .subtract(const Duration(hours: 25))
                  .millisecondsSinceEpoch ~/
              1000,
          id,
        ],
      );
      expect(
        await RecentDuplicateService.exists(repository: repository, amount: 35),
        isFalse,
      );

      await db.customStatement(
        'UPDATE recent_transaction_records SET recorded_at = ? WHERE transaction_id = ?',
        [DateTime.now().millisecondsSinceEpoch ~/ 1000, id],
      );
      await repository.deleteTransaction(id);
      expect(
        await RecentDuplicateService.exists(repository: repository, amount: 35),
        isFalse,
      );
    });

    test('升级前没有入账时间的今日账单仍会命中', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              ledgerId: 1,
              type: 'expense',
              amount: 35,
              happenedAt: d.Value(
                DateTime.now().subtract(const Duration(hours: 5)),
              ),
            ),
          );
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              ledgerId: 1,
              type: 'expense',
              amount: 77,
              happenedAt: d.Value(
                DateTime.now().subtract(const Duration(days: 2)),
              ),
            ),
          );

      expect(
        await RecentDuplicateService.exists(repository: repository, amount: 35),
        isTrue,
      );
      expect(
        await RecentDuplicateService.exists(repository: repository, amount: 77),
        isFalse,
      );
    });
  });

  test('v34 升级保留旧账单并创建入账时间表', () async {
    final dir = await Directory.systemTemp.createTemp('rancount-recent-');
    final file = File('${dir.path}/ledger.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY)');
    raw.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY,
        ledger_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');
    raw.execute("INSERT INTO transactions VALUES (1, 2, 'expense', 35)");
    raw.execute('PRAGMA user_version = 34');
    raw.dispose();

    final upgraded = BeeDatabase.forTesting(NativeDatabase(file));
    try {
      final old = await upgraded
          .customSelect('SELECT amount FROM transactions WHERE id = 1')
          .getSingle();
      expect(old.read<double>('amount'), 35);
      final tables = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'recent_transaction_records'",
          )
          .get();
      expect(tables, hasLength(1));
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}
