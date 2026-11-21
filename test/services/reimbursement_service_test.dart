import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/billing/reimbursement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase db;
  late LocalRepository repo;
  late ReimbursementService service;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    service = ReimbursementService(repo);
  });

  tearDown(() async => db.close());

  test('待报销支出与分批报销到账不污染真实收支，且准确反映账户余额', () async {
    final ledgerId = await repo.createLedger(name: '主账本');
    final payAcc = await repo.createAccount(
      ledgerId: ledgerId,
      name: '信用卡',
      type: 'credit',
      initialBalance: 0,
    );
    final receiveAcc = await repo.createAccount(
      ledgerId: ledgerId,
      name: '工资卡',
      type: 'bank',
      initialBalance: 1000,
    );
    final catId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: '差旅', kind: 'expense'),
        );
    final now = DateTime(2026, 11, 21, 12, 0);

    // 1. 记一笔 500 元待报销支出（同时标记 excludeFromStats/Budget）
    final txId = await repo.addTransaction(
      ledgerId: ledgerId,
      type: 'expense',
      amount: 500,
      categoryId: catId,
      accountId: payAcc,
      happenedAt: now,
      note: '出差高铁票',
      isReimbursable: true,
      excludeFromStats: true,
      excludeFromBudget: true,
    );

    // 真实收支均为 0，付款账户余额扣减 500
    final (inc1, exp1) = await repo.monthlyTotals(ledgerId: ledgerId, month: now);
    expect(inc1, 0);
    expect(exp1, 0);
    expect(await repo.getAccountBalance(payAcc), -500);

    final summary1 = await service.loadSummary(ledgerId);
    expect(summary1.pendingCount, 1);
    expect(summary1.settledCount, 0);
    expect(summary1.totalPendingNative, 500);
    expect(summary1.items.single.isSettled, isFalse);

    // 2. 分批报销到账 300 元到工资卡
    await service.reimburse(
      originalId: txId,
      amount: 300,
      happenedAt: now.add(const Duration(days: 2)),
      accountId: receiveAcc,
    );

    final (inc2, exp2) = await repo.monthlyTotals(ledgerId: ledgerId, month: now);
    expect(inc2, 0);
    expect(exp2, 0);
    expect(await repo.getAccountBalance(receiveAcc), 1300);

    final summary2 = await service.loadSummary(ledgerId);
    expect(summary2.pendingCount, 1);
    expect(summary2.totalPendingNative, 200);
    expect(summary2.totalReimbursedNative, 300);
    expect(summary2.items.single.isPartial, isTrue);

    // 3. 超额报销应被拦截
    await expectLater(
      service.reimburse(
        originalId: txId,
        amount: 250,
        happenedAt: now.add(const Duration(days: 3)),
        accountId: receiveAcc,
      ),
      throwsStateError,
    );

    // 4. 剩余 200 元全部报销到账
    await service.reimburse(
      originalId: txId,
      amount: 200,
      happenedAt: now.add(const Duration(days: 4)),
      accountId: receiveAcc,
    );

    final (inc3, exp3) = await repo.monthlyTotals(ledgerId: ledgerId, month: now);
    expect(inc3, 0);
    expect(exp3, 0);
    expect(await repo.getAccountBalance(receiveAcc), 1500);

    final summary3 = await service.loadSummary(ledgerId);
    expect(summary3.pendingCount, 0);
    expect(summary3.settledCount, 1);
    expect(summary3.totalPendingNative, 0);
    expect(summary3.totalReimbursedNative, 500);
    expect(summary3.items.single.isSettled, isTrue);
  });
}
