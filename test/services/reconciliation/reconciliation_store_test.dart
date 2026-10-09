import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/reconciliation/reconciliation_models.dart';
import 'package:beecount/services/reconciliation/reconciliation_store.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase db;
  late LocalRepository repo;
  late ReconciliationStore store;
  late int ledger, otherLedger, wallet, bank;
  final date = DateTime.utc(2026, 10, 5);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db, changeTracker: ChangeTracker(db));
    store = ReconciliationStore(repo);
    ledger = await repo.createLedger(name: '日常');
    otherLedger = await repo.createLedger(name: '工作');
    wallet = await repo.createAccount(
      ledgerId: ledger,
      name: '钱包',
      type: 'alipay',
      initialBalance: 100,
    );
    bank = await repo.createAccount(
      ledgerId: otherLedger,
      name: '银行卡',
      type: 'bank_card',
      initialBalance: 200,
    );
  });
  tearDown(() => db.close());

  test(
    'v36 upgrade adds local reconciliation tables and preserves existing data',
    () async {
      final old = BeeDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('CREATE TABLE preserved_test (value TEXT)');
            raw.execute("INSERT INTO preserved_test VALUES ('keep')");
            raw.execute('PRAGMA user_version=36');
          },
        ),
      );
      try {
        final upgradedStore = ReconciliationStore(LocalRepository(old));
        expect(await upgradedStore.list(), isEmpty);
        expect(
          (await old
                  .customSelect('SELECT value FROM preserved_test')
                  .getSingle())
              .read<String>('value'),
          'keep',
        );
        expect(
          (await old.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          37,
        );
      } finally {
        await old.close();
      }
    },
  );

  Future<ReconciliationSession> plan(List<Json> mutations) async {
    final snapshot = await store.snapshot();
    return ReconciliationSession(
      id: 'session',
      defaultLedgerId: ledger,
      start: DateTime.utc(2026, 10, 1),
      end: DateTime.utc(2026, 10, 9),
      fingerprint: snapshot.fingerprint,
      accounts: [
        ReconciliationAccount(
          id: wallet,
          name: '钱包',
          currency: 'CNY',
          balanceAt: date,
          complete: true,
        ),
        ReconciliationAccount(
          id: bank,
          name: '银行卡',
          currency: 'CNY',
          balanceAt: date,
          complete: true,
        ),
      ],
      proposals: [
        {'id': 'p', 'selected': true, 'mutations': mutations},
      ],
    );
  }

  Json draft({
    int? account,
    int amount = 1000,
    String type = 'expense',
    int? to,
  }) => {
    'ledgerId': ledger,
    'accountId': account ?? wallet,
    'toAccountId': to,
    'type': type,
    'amountCents': amount,
    'happenedAt': date.toIso8601String(),
  };

  test(
    'cross-ledger snapshot includes excluded transactions and more than 20 records',
    () async {
      for (var i = 0; i < 25; i++) {
        await repo.addTransaction(
          ledgerId: otherLedger,
          type: 'expense',
          amount: 1,
          accountId: wallet,
          happenedAt: date,
          excludeFromStats: true,
        );
      }
      final snapshot = await store.snapshot();
      expect(snapshot.transactions, hasLength(25));
      expect(await repo.getAccountBalance(wallet), 75);
    },
  );

  test(
    'apply is idempotent, preserves tags/details, tracks sync and undo restores rows',
    () async {
      final id = await repo.addTransaction(
        ledgerId: ledger,
        type: 'expense',
        amount: 10,
        accountId: wallet,
        happenedAt: date,
        merchant: '原商家',
        itemDescription: '商品',
        excludeFromBudget: true,
      );
      final tagId = await db
          .into(db.tags)
          .insert(TagsCompanion.insert(name: '保留标签'));
      await db
          .into(db.transactionTags)
          .insert(
            TransactionTagsCompanion.insert(transactionId: id, tagId: tagId),
          );
      final old = (await repo.getTransactionById(id))!;
      final s = await plan([
        {
          'id': 'm',
          'transactionId': id,
          'after': {
            ...reconciliationTransaction(old),
            'accountId': bank,
            'excludeFromBudget': false,
          },
        },
      ]);
      await store.save(s);
      await store.apply(s);
      await store.apply(s);
      expect(await repo.getAccountBalance(wallet), 100);
      expect(await repo.getAccountBalance(bank), 190);
      expect((await repo.getTransactionById(id))!.merchant, '原商家');
      expect((await repo.getTransactionById(id))!.excludeFromBudget, isTrue);
      expect((await db.select(db.transactionTags).get()).length, 1);
      expect(
        (await db.select(db.localChanges).get()).where(
          (c) =>
              c.entityId == id &&
              c.entityType == 'transaction' &&
              c.action == 'update',
        ),
        hasLength(1),
      );
      await store.undo(s);
      expect((await repo.getTransactionById(id))!.toJson(), old.toJson());
      expect(await repo.getAccountBalance(wallet), 90);
      expect(await repo.getAccountBalance(bank), 200);
    },
  );

  test('stale snapshot rejects application without partial writes', () async {
    final s = await plan([
      {'id': 'new', 'after': draft()},
    ]);
    await store.save(s);
    await repo.addTransaction(
      ledgerId: otherLedger,
      type: 'income',
      amount: 1,
      accountId: bank,
      happenedAt: date,
    );
    await expectLater(store.apply(s), throwsStateError);
    expect((await db.select(db.transactions).get()), hasLength(1));
    expect((await store.load(s.id))!.audit, isNull);
  });

  test(
    'reusing an account ID after data replacement cannot reuse old evidence',
    () async {
      final s = await plan([
        {'id': 'new', 'after': draft()},
      ]);
      final current = (await repo.getAccount(wallet))!;
      s.accounts[0] = ReconciliationAccount(
        id: wallet,
        name: current.name,
        currency: current.currency,
        syncId: current.syncId,
        balanceAt: date,
        complete: true,
      );
      await db.customStatement('UPDATE accounts SET sync_id=? WHERE id=?', [
        'replacement',
        wallet,
      ]);
      final replacement = await store.snapshot();
      expect(() => store.assertIdentity(s, replacement), throwsStateError);
    },
  );

  test('invalid dependency group is rejected atomically', () async {
    final s = await plan([
      {'id': 'good', 'after': draft()},
      {'id': 'bad', 'after': draft(type: 'transfer', to: wallet)},
    ]);
    await store.save(s);
    await expectLater(store.apply(s), throwsStateError);
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test(
    'database failure rolls back records, sync entries and audit together',
    () async {
      final s = await plan([
        {'id': 'first', 'after': draft()},
        {
          'id': 'second',
          'after': {...draft(), 'note': 'reject'},
        },
      ]);
      await store.save(s);
      final beforeChanges = (await db.select(db.localChanges).get()).length;
      await db.customStatement(
        "CREATE TRIGGER reject_reconciliation BEFORE INSERT ON transactions "
        "WHEN NEW.note='reject' BEGIN SELECT RAISE(ABORT, 'reject'); END",
      );
      await expectLater(store.apply(s), throwsA(isA<Exception>()));
      expect(await db.select(db.transactions).get(), isEmpty);
      expect((await db.select(db.localChanges).get()).length, beforeChanges);
      expect((await store.load(s.id))!.audit, isNull);
      expect(
        await db.customSelect('SELECT id FROM reconciliation_audits').get(),
        isEmpty,
      );
    },
  );

  test(
    'refund with a new original works regardless of mutation order and undoes as a group',
    () async {
      final s = await plan([
        {
          'id': 'refund',
          'after': {...draft(amount: -500), 'refundOfMutationId': 'original'},
        },
        {'id': 'original', 'after': draft(amount: 1000)},
      ]);
      await store.save(s);
      await store.apply(s);
      final records = await db.select(db.transactions).get();
      expect(records, hasLength(2));
      expect(
        records.singleWhere((t) => t.amount < 0).refundOfSyncId,
        records.singleWhere((t) => t.amount > 0).syncId,
      );
      expect(await repo.getAccountBalance(wallet), 95);
      await store.undo(s);
      expect(await db.select(db.transactions).get(), isEmpty);
    },
  );

  test(
    'undo refuses later edits and leaves the applied batch intact',
    () async {
      final s = await plan([
        {'id': 'new', 'after': draft()},
      ]);
      await store.save(s);
      await store.apply(s);
      final t = (await db.select(db.transactions).get()).single;
      await (db.update(db.transactions)..where((r) => r.id.equals(t.id))).write(
        const TransactionsCompanion(note: d.Value('后续修改')),
      );
      await expectLater(store.undo(s), throwsStateError);
      expect((await repo.getTransactionById(t.id))!.note, '后续修改');
      expect((await store.load(s.id))!.applied, isTrue);
    },
  );

  test(
    'delete and undo preserve attachment metadata without deleting its file',
    () async {
      final id = await repo.addTransaction(
        ledgerId: ledger,
        type: 'expense',
        amount: 10,
        accountId: wallet,
        happenedAt: date,
      );
      await db
          .into(db.transactionAttachments)
          .insert(
            TransactionAttachmentsCompanion.insert(
              transactionId: id,
              fileName: 'existing.jpg',
            ),
          );
      final s = await plan([
        {'id': 'delete', 'transactionId': id, 'after': null},
      ]);
      await store.save(s);
      await store.apply(s);
      expect(await repo.getTransactionById(id), isNull);
      expect(await db.select(db.transactionAttachments).get(), isEmpty);
      await store.undo(s);
      expect(
        (await db.select(db.transactionAttachments).get()).single.fileName,
        'existing.jpg',
      );
      expect(await repo.getTransactionById(id), isNotNull);
    },
  );
}
