import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../cloud/sync/change_tracker.dart';
import '../../cloud/sync/sync_engine.dart';
import '../../providers/database_providers.dart';
import '../../providers/sync_providers.dart';

/// A bounded, OS-scheduled fallback for confirmed transactions still waiting
/// in local_changes. Foreground and connectivity sync remain the fast path.
class BackgroundSyncRetry {
  static const _task = 'rancount_sync_confirmed';
  static const _delays = [
    Duration(minutes: 5),
    Duration(minutes: 20),
    Duration(hours: 1),
  ];
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    try {
      await Workmanager().initialize(rancountSyncRetryDispatcher);
      _initialized = true;
    } catch (_) {
      // The local record remains in local_changes for foreground retry.
    }
  }

  static Future<void> schedule(int ledgerId) async {
    if (!Platform.isAndroid || !_initialized) return;
    await _scheduleAttempt(ledgerId, 0);
  }

  static Future<void> _scheduleAttempt(int ledgerId, int attempt) async {
    if (attempt >= _delays.length) return;
    await Workmanager().registerOneOffTask(
      'rancount-sync-$ledgerId-$attempt',
      _task,
      inputData: {'ledgerId': ledgerId, 'attempt': attempt},
      initialDelay: _delays[attempt],
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<bool> _run(Map<String, dynamic>? input) async {
    final ledgerId = input?['ledgerId'] as int?;
    final attempt = input?['attempt'] as int? ?? 0;
    if (ledgerId == null || ledgerId <= 0) return true;
    final container = ProviderContainer();
    var complete = false;
    try {
      final config = await container.read(activeCloudConfigProvider.future);
      if (config.type != CloudBackendType.beecountCloud || !config.valid) {
        return true;
      }
      final db = container.read(databaseProvider);
      final tracker = ChangeTracker(db);
      if (await tracker.getUnpushedCount() == 0) return true;
      final cloud = await container.read(beecountCloudProviderInstance.future);
      if (cloud != null) {
        final engine = SyncEngine(
          db: db,
          provider: cloud,
          changeTracker: tracker,
          repo: container.read(repositoryProvider),
        );
        try {
          final result = await engine.sync(ledgerId: ledgerId.toString());
          complete = !result.hasError && await tracker.getUnpushedCount() == 0;
        } finally {
          engine.dispose();
        }
      }
    } catch (_) {
      // The next scheduled attempt may run after a transient network failure.
    } finally {
      container.dispose();
    }
    if (!complete) {
      try {
        await _scheduleAttempt(ledgerId, attempt + 1);
      } catch (_) {}
    }
    // This attempt is finished. Returning false would let WorkManager retry
    // without the three-attempt limit above.
    return true;
  }
}

@pragma('vm:entry-point')
void rancountSyncRetryDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != BackgroundSyncRetry._task) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return BackgroundSyncRetry._run(inputData);
  });
}
