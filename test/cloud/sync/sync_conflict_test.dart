import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '_fakes/fake_beecount_cloud_provider.dart';

class _RacingCloud extends FakeBeeCountCloudProvider {
  Future<void> Function()? duringPush;
  @override
  Future<void> pushChanges(
      {required List<Map<String, dynamic>> changes}) async {
    final callback = duringPush;
    duringPush = null;
    if (callback != null) await callback();
    await super.pushChanges(changes: changes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase db;
  late LocalRepository repo;
  late SyncEngine engine;
  late _RacingCloud cloud;
  late int ledger;
  late int txId;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    final tracker = ChangeTracker(db);
    repo = LocalRepository(db, changeTracker: tracker);
    cloud = _RacingCloud();
    engine =
        SyncEngine(db: db, provider: cloud, changeTracker: tracker, repo: repo);
    ledger = await repo.createLedger(name: '日常');
    txId = await repo.addTransaction(
        ledgerId: ledger,
        type: 'expense',
        amount: 80,
        syncId: 'shared-tx',
        happenedAt: DateTime(2026, 9, 1));
  });
  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  void remote({bool delete = false, double amount = 90}) {
    cloud.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'shared-tx',
        ledgerId: '$ledger',
        action: delete ? 'delete' : 'upsert',
        payload: {
          'syncId': 'shared-tx',
          'type': 'expense',
          'amount': amount,
          'happenedAt': '2026-09-01T00:00:00Z',
        });
  }

  test('a conflict arriving during upload cannot acknowledge away local edits',
      () async {
    cloud.duringPush = () async {
      remote();
      await engine.pull('');
    };
    await expectLater(
        engine.push('$ledger'), throwsA(isA<SyncConflictException>()));
    final conflict = (await engine.watchConflicts().first).single;
    expect((await repo.getTransactionById(txId))!.amount, 80);
    expect((await engine.localConflictVersion(conflict))['amount'], 80);
  });

  test('remote update is retained and upload blocked until explicitly resolved',
      () async {
    remote();
    await expectLater(
        engine.push('$ledger'), throwsA(isA<SyncConflictException>()));
    expect((await repo.getTransactionById(txId))!.amount, 80);
    expect(cloud.pushedBatches, isEmpty);
    final conflict = (await engine.watchConflicts().first).single;
    expect(conflict.rawChangeJson, contains('90'));
    await engine.resolveConflict(conflict,
        keepLocal: false,
        expectedLocal: await engine.localConflictVersion(conflict));
    expect((await repo.getTransactionById(txId))!.amount, 90);
    expect(await engine.watchConflicts().first, isEmpty);
  });

  test(
      'remote delete cannot remove a pending edit; keeping local retains pending upload',
      () async {
    remote(delete: true);
    await engine.pull('');
    final conflict = (await engine.watchConflicts().first).single;
    expect(await repo.getTransactionById(txId), isNotNull);
    await engine.resolveConflict(conflict,
        keepLocal: true,
        expectedLocal: await engine.localConflictVersion(conflict));
    expect((await repo.getTransactionById(txId))!.amount, 80);
    expect(await engine.watchConflicts().first, isEmpty);
    expect(await engine.changeTracker.getUnpushedCount(), greaterThan(0));
  });

  test('resolution rejects a newer remote version not yet reviewed', () async {
    remote();
    await engine.pull('');
    final conflict = (await engine.watchConflicts().first).single;
    final local = await engine.localConflictVersion(conflict);
    remote(amount: 100);
    await expectLater(
        engine.resolveConflict(conflict,
            keepLocal: false, expectedLocal: local),
        throwsStateError);
    expect((await repo.getTransactionById(txId))!.amount, 80);
    expect(await engine.watchConflicts().first, hasLength(2));
  });
}
