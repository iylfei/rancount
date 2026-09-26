import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppVisualStyle {
  classic,
  liquidGlass;

  static AppVisualStyle? parse(Object? value) => switch (value) {
        'classic' => classic,
        'liquidGlass' => liquidGlass,
        _ => null,
      };
}

enum GlassQuality {
  automatic,
  simplified;

  static GlassQuality? parse(Object? value) => switch (value) {
        'automatic' => automatic,
        'simplified' => simplified,
        _ => null,
      };
}

/// These preferences belong to this installation, not the cloud theme profile.
class AppAppearanceSettings {
  final AppVisualStyle visualStyle;
  final GlassQuality glassQuality;
  final bool interfaceAnimations;
  final bool hapticsEnabled;

  const AppAppearanceSettings({
    required this.visualStyle,
    this.glassQuality = GlassQuality.automatic,
    this.interfaceAnimations = true,
    this.hapticsEnabled = true,
  });

  static bool get supportsLiquidGlass =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  factory AppAppearanceSettings.defaults({required bool isAndroid}) =>
      AppAppearanceSettings(
        visualStyle:
            isAndroid ? AppVisualStyle.liquidGlass : AppVisualStyle.classic,
      );

  /// The caller reloads preferences when another engine may have changed them.
  factory AppAppearanceSettings.fromPreferences(
    SharedPreferences preferences, {
    bool? isAndroid,
  }) {
    final defaults = AppAppearanceSettings.defaults(
      isAndroid: isAndroid ?? supportsLiquidGlass,
    );
    return AppAppearanceSettings(
      visualStyle: AppVisualStyle.parse(preferences.get('visualStyle')) ??
          defaults.visualStyle,
      glassQuality: GlassQuality.parse(preferences.get('glassQuality')) ??
          defaults.glassQuality,
      interfaceAnimations: preferences.get('interfaceAnimations') is bool
          ? preferences.getBool('interfaceAnimations')!
          : defaults.interfaceAnimations,
      hapticsEnabled: preferences.get('hapticsEnabled') is bool
          ? preferences.getBool('hapticsEnabled')!
          : defaults.hapticsEnabled,
    );
  }
}
