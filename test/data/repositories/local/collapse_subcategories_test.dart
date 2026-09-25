import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db, changeTracker: ChangeTracker(db));
  });

  tearDown(() => db.close());

  test('二级分类的交易、周期账单和预算归入各自一级分类', () async {
    final ledgerId = await repo.createLedger(name: '测试账本');
    final expense = await repo.createCategory(name: '餐饮', kind: 'expense');
    final income = await repo.createCategory(name: '工资', kind: 'income');
    final lunch = await repo.createSubCategory(
        parentId: expense, name: '午餐', kind: 'expense');
    final salary = await repo.createSubCategory(
        parentId: income, name: '基本工资', kind: 'income');

    final expenseTx = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 12,
            categoryId: d.Value(lunch),
            syncId: const d.Value('expense-tx'),
          ),
        );
    final incomeTx = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'income',
            amount: 100,
            categoryId: d.Value(salary),
            syncId: const d.Value('income-tx'),
          ),
        );
    final directTx = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 5,
            categoryId: d.Value(expense),
          ),
        );
    final recurringId = await db.into(db.recurringTransactions).insert(
          RecurringTransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 20,
            frequency: 'monthly',
            startDate: DateTime(2026, 1, 1),
            categoryId: d.Value(lunch),
          ),
        );
    final budgetId = await db.into(db.budgets).insert(
          BudgetsCompanion.insert(
            ledgerId: ledgerId,
            amount: 300,
            type: const d.Value('category'),
            categoryId: d.Value(lunch),
            syncId: const d.Value('lunch-budget'),
          ),
        );

    final result = await repo.collapseSubcategories();
    expect(result, (
      categories: 2,
      transactions: 2,
      recurring: 1,
      budgets: 1,
    ));
    expect(await repo.getCategoryById(lunch), isNull);
    expect(await repo.getCategoryById(salary), isNull);
    expect(await repo.getCategoryById(expense), isNotNull);
    expect(await repo.getCategoryById(income), isNotNull);
    expect((await (db.select(db.transactions)
              ..where((t) => t.id.equals(expenseTx)))
            .getSingle())
        .categoryId, expense);
    expect((await (db.select(db.transactions)
              ..where((t) => t.id.equals(incomeTx)))
            .getSingle())
        .categoryId, income);
    expect((await (db.select(db.transactions)
              ..where((t) => t.id.equals(directTx)))
            .getSingle())
        .categoryId, expense);
    expect((await (db.select(db.recurringTransactions)
              ..where((r) => r.id.equals(recurringId)))
            .getSingle())
        .categoryId, expense);
    expect((await (db.select(db.budgets)
              ..where((b) => b.id.equals(budgetId)))
            .getSingle())
        .categoryId, expense);

    final changes = await (db.select(db.localChanges)
          ..where((c) => c.action.equals('update') | c.action.equals('delete')))
        .get();
    expect(changes.where((c) => c.entityType == 'transaction').length, 2);
    expect(changes.where((c) => c.entityType == 'budget').length, 1);
    expect(changes.where((c) => c.entityType == 'category' && c.action == 'delete').length, 2);
    expect((await repo.collapseSubcategories()).categories, 0);
  });

  test('无有效父级时事务回滚，保留全部二级分类', () async {
    final parent = await repo.createCategory(name: '餐饮', kind: 'expense');
    final child = await repo.createSubCategory(
        parentId: parent, name: '午餐', kind: 'expense');
    final orphan = await repo.createCategory(
      name: '失主分类',
      kind: 'expense',
      level: 2,
      parentId: 9999,
    );

    await expectLater(repo.collapseSubcategories(), throwsStateError);
    expect(await repo.getCategoryById(child), isNotNull);
    expect(await repo.getCategoryById(orphan), isNotNull);
  });
}
