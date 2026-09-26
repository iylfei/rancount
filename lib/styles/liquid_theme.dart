import 'package:flutter/material.dart';

/// App-owned appearance contract. Rendering packages stay behind UI adapters.
@immutable
class LiquidTheme extends ThemeExtension<LiquidTheme> {
  final bool enabled;
  final bool simplified;
  final bool animationsEnabled;
  final bool hapticsEnabled;

  const LiquidTheme({
    this.enabled = false,
    this.simplified = false,
    this.animationsEnabled = true,
    this.hapticsEnabled = true,
  });

  static LiquidTheme of(BuildContext context) =>
      Theme.of(context).extension<LiquidTheme>() ?? const LiquidTheme();
  static bool isActive(BuildContext context) => of(context).enabled;

  static bool motionOf(BuildContext context) =>
      of(context).animationsEnabled && !MediaQuery.disableAnimationsOf(context);

  static Color accent(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF71AEFF)
      : const Color(0xFF0065E8);

  @override
  LiquidTheme copyWith({
    bool? enabled,
    bool? simplified,
    bool? animationsEnabled,
    bool? hapticsEnabled,
  }) => LiquidTheme(
    enabled: enabled ?? this.enabled,
    simplified: simplified ?? this.simplified,
    animationsEnabled: animationsEnabled ?? this.animationsEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
  );

  @override
  LiquidTheme lerp(covariant LiquidTheme? other, double t) =>
      other == null || t < .5 ? this : other;
}
