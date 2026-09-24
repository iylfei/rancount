import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase db;
  late LocalRepository repo;
  late BillCreationService service;
  late int ledger;
  late int account;
  late int parent;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'account_feature_enabled': false});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    service = BillCreationService(repo);
    final other = await repo.createLedger(name: '另一个账本');
    await repo.createAccount(ledgerId: other, name: '外部现金');
    ledger = await repo.createLedger(name: '当前账本');
    account = await repo.createAccount(ledgerId: ledger, name: '现金');
    parent = await repo.createCategory(name: '餐饮', kind: 'expense');
    await repo.createCategory(
        name: '早餐', kind: 'expense', parentId: parent, level: 2);
  });
  tearDown(() => db.close());

  BillInfo bill({String category = '餐饮', String currency = 'CNY'}) => BillInfo(
      type: BillType.expense,
      amount: -25,
      time: DateTime(2026, 9, 1),
      category: category,
      account: '现金',
      currency: currency);

  test(
      'confirmation preserves parent category and scoped account even when feature hidden',
      () async {
    final id = await service.createFromBill(
        bill: bill(),
        ledgerId: ledger,
        syncId: 'reviewed',
        confirmedImage: true,
        autoAddTags: false);
    final tx = (await repo.getTransactionById(id!))!;
    expect(tx.categoryId, parent);
    expect(tx.accountId, account);
    expect(await repo.getAccountBalance(account), -25);
  });

  test('unknown category or conflicting currency cannot fall back', () async {
    for (final input in [bill(category: '餐'), bill(currency: 'USD')]) {
      await expectLater(
          service.createFromBill(
              bill: input,
              ledgerId: ledger,
              confirmedImage: true,
              autoAddTags: false),
          throwsStateError);
    }
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('concurrent retries with the same draft id create one transaction',
      () async {
    final ids = await Future.wait(List.generate(
        2,
        (_) => service.createFromBill(
            bill: bill(),
            ledgerId: ledger,
            syncId: 'one',
            confirmedImage: true,
            autoAddTags: false)));
    expect(ids[0], ids[1]);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });
}
