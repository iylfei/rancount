import '../../providers/appearance_providers.dart';
import '../../styles/app_theme.dart';
import '../../styles/liquid_theme.dart';
import '../../widgets/ui/liquid_glass.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/security_providers.dart';
import '../../services/billing/background_sync_retry.dart';
import '../auth/app_lock_screen.dart';
import 'image_draft_page.dart';

const _dialogChannel = MethodChannel('com.tntlikely.beecount/capture_dialog');

Future<void> runScreenshotDialog() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final container = ProviderContainer();
  restoreAppearanceSettings(container.read, prefs);
  await Future.wait([
    container.read(themeModeInitProvider.future),
    container.read(primaryColorInitProvider.future),
  ]);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const _ScreenshotDialogApp(),
    ),
  );
}

final _dialogInitProvider = FutureProvider<File>((ref) async {
  final path = await _dialogChannel.invokeMethod<String>('imagePath');
  if (path == null || !await File(path).exists()) {
    throw StateError('截图已失效，请关闭后重新截图');
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  ref.read(currentLedgerIdProvider.notifier).state =
      prefs.getInt('current_ledger_id') ?? 1;
  // Resolve cloud configuration before constructing the repository so confirmed
  // writes have their ChangeTracker even when the main app is not running.
  await ref.read(activeCloudConfigProvider.future);
  await Future.wait([
    ref.read(securityInitProvider.future),
    ref.read(baseCurrencyInitProvider.future),
    BackgroundSyncRetry.initialize(),
  ]);
  if (await ref.read(currentLedgerProvider.future) == null) {
    throw StateError('请先在 rancount 中完成账本设置');
  }
  return File(path);
});

class _ScreenshotDialogApp extends ConsumerStatefulWidget {
  const _ScreenshotDialogApp();

  @override
  ConsumerState<_ScreenshotDialogApp> createState() =>
      _ScreenshotDialogAppState();
}

class _ScreenshotDialogAppState extends ConsumerState<_ScreenshotDialogApp>
    with WidgetsBindingObserver {
  bool _unlockedOnce = false;
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wasPaused = true;
    if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      if (ref.read(appLockEnabledProvider)) {
        ref.read(isAppLockedProvider.notifier).state = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final init = ref.watch(_dialogInitProvider);
    final locked = ref.watch(isAppLockedProvider);
    final appearance = LiquidTheme(
      enabled:
          AppAppearanceSettings.supportsLiquidGlass &&
          ref.watch(visualStyleProvider) == AppVisualStyle.liquidGlass,
      simplified: ref.watch(glassQualityProvider) == GlassQuality.simplified,
      animationsEnabled: ref.watch(interfaceAnimationsProvider),
      hapticsEnabled: ref.watch(hapticsEnabledProvider),
    );
    final primary = ref.watch(primaryColorProvider);
    final platform = Theme.of(context).platform;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(
        brightness: Brightness.light,
        classicPrimary: primary,
        platform: platform,
        appearance: appearance,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        classicPrimary: primary,
        platform: platform,
        appearance: appearance,
      ),
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => Stack(
        children: [
          LiquidBackdrop(child: child ?? const SizedBox.shrink()),
          if (init.hasValue && locked)
            const Positioned.fill(child: AppLockScreen()),
        ],
      ),
      home: init.when(
        loading: () => const _DialogStatus(),
        error: (error, _) => _DialogStatus(
          message: error is StateError
              ? error.message.toString()
              : '初始化失败，请关闭后重试',
        ),
        data: (image) {
          if (!locked) _unlockedOnce = true;
          return Stack(
            children: [
              if (_unlockedOnce)
                ImageDraftPage(
                  image: image,
                  ownsImage: true,
                  onClose: () => _dialogChannel.invokeMethod<void>('close'),
                  // The temporary engine is destroyed on close. Queue durable
                  // WorkManager retries instead of starting a disposable sync job.
                  onSaved: (id) async {
                    await _dialogChannel.invokeMethod<void>('saved');
                    try {
                      await BackgroundSyncRetry.schedule(id, immediately: true);
                    } catch (_) {
                      // The confirmed local change remains queued for app startup.
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DialogStatus extends StatelessWidget {
  final String? message;
  const _DialogStatus({this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('截图记账'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _dialogChannel.invokeMethod<void>('close'),
      ),
    ),
    body: Center(
      child: message == null
          ? const CircularProgressIndicator()
          : Padding(padding: const EdgeInsets.all(24), child: Text(message!)),
    ),
  );
}
