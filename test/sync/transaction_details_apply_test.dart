import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/entity_serializer.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

import '../cloud/sync/_fakes/fake_beecount_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new device restores details and old partial change preserves them',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    final tracker = ChangeTracker(db);
    final repo = LocalRepository(db, changeTracker: tracker);
    final provider = FakeBeeCountCloudProvider();
    final engine = SyncEngine(
      db: db,
      provider: provider,
      changeTracker: tracker,
      repo: repo,
    );
    try {
      final ledgerId = await repo.createLedger(name: '账本');
      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'refund-1',
        ledgerId: '$ledgerId',
        payload: {
          'syncId': 'refund-1',
          'type': 'expense',
          'amount': -30,
          'happenedAt': '2026-09-23T10:00:00Z',
          'merchant': '书店',
          'itemDescription': '图书',
          'paymentChannel': '微信支付',
          'refundOfSyncId': 'purchase-1',
        },
      );
      await engine.pull('');
      var restored = await repo.getTransactionBySyncId('refund-1');
      expect(restored, isNotNull);
      expect(restored!.merchant, '书店');
      expect(restored.itemDescription, '图书');
      expect(restored.paymentChannel, '微信支付');
      expect(restored.refundOfSyncId, 'purchase-1');

      final outgoing = EntitySerializer.serializeTransaction(restored);
      expect(outgoing['merchant'], '书店');
      expect(outgoing['itemDescription'], '图书');
      expect(outgoing['paymentChannel'], '微信支付');
      expect(outgoing['refundOfSyncId'], 'purchase-1');

      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'refund-1',
        ledgerId: '$ledgerId',
        payload: {
          'syncId': 'refund-1',
          'type': 'expense',
          'amount': -20,
          'happenedAt': '2026-09-23T10:00:00Z',
          'note': '旧客户端修改',
        },
      );
      await engine.pull('');
      restored = await repo.getTransactionBySyncId('refund-1');
      expect(restored!.amount, -20);
      expect(restored.merchant, '书店');
      expect(restored.itemDescription, '图书');
      expect(restored.paymentChannel, '微信支付');
      expect(restored.refundOfSyncId, 'purchase-1');
    } finally {
      engine.dispose();
      await db.close();
    }
  });
}
