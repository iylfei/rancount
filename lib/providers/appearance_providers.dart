import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_appearance.dart';

export '../models/app_appearance.dart';

final visualStyleProvider = StateProvider<AppVisualStyle>(
  (ref) => AppAppearanceSettings.defaults(
    isAndroid: AppAppearanceSettings.supportsLiquidGlass,
  ).visualStyle,
);

final glassQualityProvider =
    StateProvider<GlassQuality>((ref) => GlassQuality.automatic);
final interfaceAnimationsProvider = StateProvider<bool>((ref) => true);
final hapticsEnabledProvider = StateProvider<bool>((ref) => true);

/// Shared by the main app and the separate screenshot-billing engine.
/// Refresh SharedPreferences before calling this after crossing engine bounds.
void restoreAppearanceSettings(
  T Function<T>(ProviderListenable<T>) read,
  SharedPreferences preferences,
) {
  final saved = AppAppearanceSettings.fromPreferences(preferences);
  read(visualStyleProvider.notifier).state = saved.visualStyle;
  read(glassQualityProvider.notifier).state = saved.glassQuality;
  read(interfaceAnimationsProvider.notifier).state = saved.interfaceAnimations;
  read(hapticsEnabledProvider.notifier).state = saved.hapticsEnabled;
}

final appearanceInitProvider = FutureProvider<void>((ref) async {
  final preferences = await SharedPreferences.getInstance();
  restoreAppearanceSettings(ref.read, preferences);

  ref.listen<AppVisualStyle>(visualStyleProvider, (previous, next) async {
    await preferences.setString('visualStyle', next.name);
  });
  ref.listen<GlassQuality>(glassQualityProvider, (previous, next) async {
    await preferences.setString('glassQuality', next.name);
  });
  ref.listen<bool>(interfaceAnimationsProvider, (previous, next) async {
    await preferences.setBool('interfaceAnimations', next);
  });
  ref.listen<bool>(hapticsEnabledProvider, (previous, next) async {
    await preferences.setBool('hapticsEnabled', next);
  });
});
