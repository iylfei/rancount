part of 'sync_engine.dart';

class SyncConflictException implements Exception {
  @override
  String toString() => '本机与云端存在不同修改，请到云同步页面处理冲突';
}

extension SyncEngineConflicts on SyncEngine {
  Stream<List<SyncPullError>> watchConflicts() => (db.select(db.syncPullErrors)
        ..where((e) =>
            e.errorClass.equals('SyncConflictException') &
            e.resolvedAt.isNull())
        ..orderBy([(e) => d.OrderingTerm.desc(e.changeId)]))
      .watch();

  Future<bool> _retainConflict(BeeCountCloudSyncChange change) async {
    final pending = await (db.select(db.localChanges)
          ..where((c) =>
              c.entityType.equals(change.entityType) &
              c.entitySyncId.equals(change.entitySyncId) &
              c.pushedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (pending == null) return false;
    await pullErrors.record(
        change: change,
        error: SyncConflictException(),
        stackTrace: StackTrace.current);
    return true;
  }

  /// Read before every upload, including direct push and full push callers.
  Future<void> _checkConflictsBeforePush() async {
    await pull('');
    await _assertNoConflicts();
  }

  Future<void> _assertNoConflicts() async {
    final unresolved = await (db.select(db.syncPullErrors)
          ..where((e) => e.resolvedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (unresolved != null) {
      if (unresolved.errorClass == 'SyncConflictException') {
        throw SyncConflictException();
      }
      throw StateError('云端变更尚未完整读取，暂缓上传以保护本机修改');
    }
  }

  Future<void> _markPushedUnlessConflicted(List<int> ids) async {
    var blocked = false;
    await db.transaction(() async {
      final conflicts = await (db.select(db.syncPullErrors)
            ..where((e) =>
                e.errorClass.equals('SyncConflictException') &
                e.resolvedAt.isNull()))
          .get();
      final keys =
          conflicts.map((e) => '${e.entityType}/${e.entitySyncId}').toSet();
      final rows = await (db.select(db.localChanges)
            ..where((c) => c.id.isIn(ids)))
          .get();
      final safe = rows
          .where((c) => !keys.contains('${c.entityType}/${c.entitySyncId}'))
          .toList();
      blocked = safe.length != rows.length;
      await changeTracker.markPushed(safe.map((c) => c.id).toList());
    });
    if (blocked) throw SyncConflictException();
  }

  Future<Map<String, dynamic>> localConflictVersion(
      SyncPullError conflict) async {
    final pending = await (db.select(db.localChanges)
          ..where((c) =>
              c.entityType.equals(conflict.entityType) &
              c.entitySyncId.equals(conflict.entitySyncId) &
              c.pushedAt.isNull())
          ..orderBy([(c) => d.OrderingTerm.desc(c.id)])
          ..limit(1))
        .getSingleOrNull();
    if (pending == null) throw StateError('冲突状态已变化，请刷新');
    if (pending.action == 'delete') return {'action': 'delete'};
    return _serializeEntityForPush(
        entityType: pending.entityType,
        entityId: pending.entityId,
        ledgerId: pending.ledgerId);
  }

  Future<void> resolveConflict(
    SyncPullError conflict, {
    required bool keepLocal,
    required Map<String, dynamic> expectedLocal,
  }) async {
    // Refresh first so a choice never unknowingly discards a newer remote edit.
    await pull('');
    await db.transaction(() async {
      final latest = await (db.select(db.syncPullErrors)
            ..where((e) =>
                e.entityType.equals(conflict.entityType) &
                e.entitySyncId.equals(conflict.entitySyncId) &
                e.errorClass.equals('SyncConflictException') &
                e.resolvedAt.isNull())
            ..orderBy([(e) => d.OrderingTerm.desc(e.changeId)])
            ..limit(1))
          .getSingleOrNull();
      if (latest?.changeId != conflict.changeId ||
          jsonEncode(await localConflictVersion(conflict)) !=
              jsonEncode(expectedLocal)) {
        throw StateError('账单已发生变化，请重新查看后选择');
      }
      final pending = await (db.select(db.localChanges)
            ..where((c) =>
                c.entityType.equals(conflict.entityType) &
                c.entitySyncId.equals(conflict.entitySyncId) &
                c.pushedAt.isNull()))
          .get();
      if (keepLocal) {
        // New change ID: a late acknowledgement of an older upload cannot
        // accidentally acknowledge the user's new conflict resolution.
        final latestLocal = pending.reduce((a, b) => a.id > b.id ? a : b);
        await changeTracker.markPushed(pending.map((c) => c.id).toList());
        if (ChangeTracker.userGlobalEntityTypes
            .contains(latestLocal.entityType)) {
          await changeTracker.recordUserGlobalChange(
              entityType: latestLocal.entityType,
              entityId: latestLocal.entityId,
              entitySyncId: latestLocal.entitySyncId,
              action: latestLocal.action,
              payloadJson: latestLocal.payloadJson);
        } else {
          await changeTracker.recordLedgerChange(
              entityType: latestLocal.entityType,
              entityId: latestLocal.entityId,
              entitySyncId: latestLocal.entitySyncId,
              ledgerId: latestLocal.ledgerId,
              action: latestLocal.action,
              payloadJson: latestLocal.payloadJson);
        }
      } else {
        await changeTracker.markPushed(pending.map((c) => c.id).toList());
        final raw = jsonDecode(conflict.rawChangeJson) as Map<String, dynamic>;
        await applyRemoteChange(BeeCountCloudSyncChange(
            changeId: raw['change_id'] as int,
            ledgerId: raw['ledger_id'] as String,
            entityType: raw['entity_type'] as String,
            entitySyncId: raw['entity_sync_id'] as String,
            action: raw['action'] as String,
            updatedByDeviceId: raw['updated_by_device_id'] as String?,
            updatedAt: raw['updated_at'] as String?,
            payload: raw['payload'] == null
                ? null
                : Map<String, dynamic>.from(raw['payload'] as Map)));
      }
      await (db.update(db.syncPullErrors)
            ..where((e) =>
                e.entityType.equals(conflict.entityType) &
                e.entitySyncId.equals(conflict.entitySyncId) &
                e.errorClass.equals('SyncConflictException') &
                e.resolvedAt.isNull()))
          .write(SyncPullErrorsCompanion(
              resolvedAt: d.Value(DateTime.now().toUtc()),
              userAction: d.Value(keepLocal ? 'keep_local' : 'use_remote')));
    });
    _emit(PullCompleted(ledgerId: conflict.ledgerExternalId ?? '', applied: 1));
    triggerAutoSync(reason: 'conflict_resolved');
  }
}
