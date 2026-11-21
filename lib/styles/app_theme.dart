import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/ui/liquid_glass.dart';
import 'liquid_theme.dart';

ThemeData buildAppTheme({
  required Brightness brightness,
  required Color classicPrimary,
  required TargetPlatform platform,
  required LiquidTheme appearance,
}) {
  final dark = brightness == Brightness.dark;
  final base = dark
      ? BeeTheme.darkTheme(platform: platform)
      : BeeTheme.lightTheme(platform: platform);
  if (!appearance.enabled) {
    final classic = dark
        ? base.copyWith(
            colorScheme: base.colorScheme.copyWith(primary: classicPrimary),
            primaryColor: classicPrimary,
          )
        : base.copyWith(
            colorScheme: base.colorScheme.copyWith(primary: classicPrimary),
            primaryColor: classicPrimary,
            scaffoldBackgroundColor: Colors.white,
            dividerColor: Colors.black.withValues(alpha: .06),
            listTileTheme: const ListTileThemeData(
              dense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
              iconColor: Color(0xFF111827),
            ),
            dialogTheme: base.dialogTheme.copyWith(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titleTextStyle: base.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w600,
              ),
              contentTextStyle: base.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: classicPrimary,
                textStyle: base.textTheme.labelLarge,
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: classicPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
              backgroundColor: classicPrimary,
              foregroundColor: Colors.white,
            ),
            bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
              selectedItemColor: classicPrimary,
              type: BottomNavigationBarType.fixed,
            ),
            cardTheme: base.cardTheme.copyWith(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: EdgeInsets.zero,
            ),
          );
    return classic.copyWith(extensions: [appearance]);
  }
  final primary = LiquidTheme.accent(brightness);
  final surface = dark ? const Color(0xFF202C3E) : const Color(0xFFF8FBFF);
  final text = dark ? const Color(0xFFF5F8FF) : const Color(0xFF17253B);
  final secondaryText = dark
      ? const Color(0xFFB6C4D8)
      : const Color(0xFF53647C);
  final outline = dark ? const Color(0xFF3D4B60) : const Color(0xFFD5E0EF);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF091A31) : Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: secondaryText,
        outline: outline,
        outlineVariant: outline.withValues(alpha: .6),
      );
  const shape = StadiumBorder();
  ButtonStyle button({bool filled = false, bool outlined = false}) =>
      ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
        shape: const WidgetStatePropertyAll(shape),
        elevation: const WidgetStatePropertyAll(0),
        enableFeedback: false,
        splashFactory: NoSplash.splashFactory,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? surface.withValues(alpha: .42)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? secondaryText.withValues(alpha: .5)
              : filled
              ? scheme.onPrimary
              : text,
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundBuilder: (context, states, child) => LiquidButtonLayer(
          states: Set.of(states),
          prominent: filled,
          outlined: outlined,
          child: child ?? const SizedBox.shrink(),
        ),
      );
  return ThemeData(
    useMaterial3: true,
    platform: platform,
    brightness: brightness,
    colorScheme: scheme,
    primaryColor: primary,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: surface,
    dividerColor: outline.withValues(alpha: .5),
    extensions: [appearance],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: _LiquidPageTransitionsBuilder()},
    ),
    textTheme: base.textTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            color: text,
            fontWeight: FontWeight.w700,
            letterSpacing: -.7,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            color: text,
            fontWeight: FontWeight.w700,
            letterSpacing: -.35,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            color: text,
            fontWeight: FontWeight.w600,
          ),
        ),
    iconTheme: IconThemeData(color: text, size: 22),
    appBarTheme: AppBarTheme(
      // Transparent bars cannot infer icon contrast from their own background.
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      backgroundColor: surface.withValues(alpha: .86),
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Colors.white.withValues(alpha: dark ? .1 : .7),
          width: .8,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      barrierColor: Colors.black.withValues(alpha: dark ? .36 : .22),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: secondaryText,
        fontSize: 15,
        height: 1.45,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(alpha: .25),
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: secondaryText.withValues(alpha: .35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: primary,
      textColor: text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: secondaryText),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button().copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? secondaryText.withValues(alpha: .5)
              : primary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: button(filled: true)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button(filled: true)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button(outlined: true)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: Colors.white.withValues(alpha: dark ? .18 : .72),
            width: 1,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withValues(alpha: dark ? .76 : .84);
          }
          return surface.withValues(alpha: dark ? .42 : .55);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return text;
        }),
        enableFeedback: false,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: button().copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
        minimumSize: const WidgetStatePropertyAll(Size(42, 42)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: const StadiumBorder(),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primary.withValues(alpha: .14),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: text),
    ),
    dividerTheme: DividerThemeData(
      color: outline.withValues(alpha: .5),
      thickness: .6,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? primary : outline,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class _LiquidPageTransitionsBuilder extends PageTransitionsBuilder {
  const _LiquidPageTransitionsBuilder();
  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 210);
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Pause live geometry-tracking shader passes while sliding to maintain
    // high frame rates, then seamlessly restore full refraction once settled.
    final page = RepaintBoundary(
      child: GlassTransitionBarrier(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: LiquidBackdrop(force: true, child: child),
      ),
    );
    if (!LiquidTheme.motionOf(context)) return page;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween(
        begin: const Offset(.14, 0),
        end: Offset.zero,
      ).animate(curved),
      child: page,
    );
  }
}
