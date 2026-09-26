import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as renderer;
import '../../styles/liquid_theme.dart';
import 'compatible_glass_layer.dart';

/// A bounded material: only prominent controls sample the live backdrop.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool prominent;
  final Color? tintColor;
  final double? tintOpacity;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.prominent = true,
    this.tintColor,
    this.tintOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final appearance = LiquidTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final nested =
        context.dependOnInheritedWidgetOfExactType<_GlassScope>() != null;
    final padded = Padding(padding: padding, child: child);
    final content = prominent && !nested ? _GlassScope(child: padded) : padded;
    if (!appearance.enabled) return Padding(padding: margin, child: content);
    final highContrast = MediaQuery.highContrastOf(context);
    // Use one contour for the shader, clipping and Flutter's antialiased rim.
    final shape = renderer.LiquidRoundedRectangle(borderRadius: borderRadius);
    final tint =
        tintColor ?? (dark ? const Color(0xFF202C3E) : const Color(0xFFF8FBFF));
    final settings = renderer.LiquidGlassSettings(
      thickness: 18,
      blur: 8,
      refractiveIndex: 1.18,
      lightIntensity: .18,
      ambientStrength: .04,
      saturation: 1.12,
      glassColor: tint.withValues(
        alpha:
            tintOpacity ??
            (tintColor != null
                ? .96
                : dark
                ? .60
                : .48),
      ),
    );
    Widget material;
    if (nested && prominent && !highContrast) {
      material = DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: tintColor != null ? .96 : .08),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    } else if (highContrast || !prominent) {
      material = DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: highContrast ? 1 : .92),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    } else if (appearance.simplified ||
        !ui.ImageFilter.isShaderFilterSupported) {
      material = renderer.FakeGlass(
        shape: shape,
        settings: settings,
        child: const SizedBox.expand(),
      );
    } else {
      material = CompatibleGlassLayer(
        settings: settings,
        child: renderer.LiquidGlass(
          shape: shape,
          child: const SizedBox.expand(),
        ),
      );
    }
    // Keep controls in the normal Flutter paint tree. The renderer owns only
    // the backdrop, so shader loading or a failed geometry pass cannot hide
    // navigation, dialog contents or their accessible labels.
    final surface = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(child: IgnorePointer(child: material)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      ],
    );
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF183458,
              ).withValues(alpha: dark ? .16 : .07),
              blurRadius: 22,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .22 : .62),
              width: 1,
            ),
          ),
          child: surface,
        ),
      ),
    );
  }
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({required super.child});
  @override
  bool updateShouldNotify(_GlassScope oldWidget) => false;
}

class _BackdropScope extends InheritedWidget {
  const _BackdropScope({required super.child});
  @override
  bool updateShouldNotify(_BackdropScope oldWidget) => false;
}

class LiquidBackdrop extends StatelessWidget {
  final Widget child;
  final bool force;
  const LiquidBackdrop({super.key, required this.child, this.force = false});
  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context) ||
        (!force &&
            context.dependOnInheritedWidgetOfExactType<_BackdropScope>() !=
                null)) {
      return child;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _BackdropScope(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [
                    Color(0xFF101722),
                    Color(0xFF17253A),
                    Color(0xFF0C111C),
                  ]
                : const [
                    Color(0xFFF1F6FC),
                    Color(0xFFE2EDFC),
                    Color(0xFFF7F9FD),
                  ],
            stops: const [0, .52, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Shared feedback prevents a nested control and its parent vibrating twice.
class GlassFeedback {
  static final Stopwatch _clock = Stopwatch()..start();
  static int _last = -100;
  static bool _accept(BuildContext context) {
    if (LiquidTheme.isActive(context) &&
        !LiquidTheme.of(context).hapticsEnabled) {
      return false;
    }
    final now = _clock.elapsedMilliseconds;
    if (now - _last < 55) return false;
    _last = now;
    return true;
  }

  static void selection(BuildContext context) {
    if (_accept(context)) HapticFeedback.selectionClick();
  }

  static void impact(BuildContext context) {
    if (_accept(context)) HapticFeedback.lightImpact();
  }
}

/// Pointer observation only: scrolling, nested taps and long presses keep their
/// existing gesture recognizers. It never dispatches a business action.
class GlassPressEffect extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;
  const GlassPressEffect({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = .96,
  });
  @override
  State<GlassPressEffect> createState() => _GlassPressEffectState();
}

class _GlassPressEffectState extends State<GlassPressEffect> {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;
  Alignment _light = Alignment.center;
  void _reset() {
    _pointer = null;
    _origin = null;
    _pressed = false;
  }

  @override
  void didUpdateWidget(GlassPressEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!LiquidTheme.isActive(context)) _reset();
  }

  void _release() {
    _pointer = null;
    _origin = null;
    if (_pressed && mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !LiquidTheme.isActive(context)) return widget.child;
    final motion = LiquidTheme.motionOf(context);
    return Listener(
      onPointerDown: (event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        _origin = event.position;
        final box = context.findRenderObject() as RenderBox?;
        if (box != null &&
            box.hasSize &&
            box.size.width > 0 &&
            box.size.height > 0) {
          final local = box.globalToLocal(event.position);
          _light = Alignment(
            (local.dx / box.size.width * 2 - 1).clamp(-1, 1),
            (local.dy / box.size.height * 2 - 1).clamp(-1, 1),
          );
        }
        setState(() => _pressed = true);
      },
      onPointerMove: (event) {
        if (event.pointer == _pointer &&
            _origin != null &&
            (event.position - _origin!).distance > 12) {
          _release();
        }
      },
      onPointerUp: (event) {
        if (event.pointer == _pointer) _release();
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) _release();
      },
      child: AnimatedScale(
        scale: _pressed && motion ? widget.scale : 1,
        duration: motion
            ? Duration(milliseconds: _pressed ? 100 : 280)
            : Duration.zero,
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: _pressed
                ? RadialGradient(
                    center: _light,
                    radius: 1,
                    colors: [
                      Colors.white.withValues(alpha: .24),
                      Colors.white.withValues(alpha: .02),
                    ],
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class GlassPressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final bool selectionFeedback;
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selectionFeedback = false,
  });
  @override
  Widget build(BuildContext context) {
    final active = enabled && (onTap != null || onLongPress != null);
    void feedback() {
      if (!LiquidTheme.isActive(context)) return;
      selectionFeedback
          ? GlassFeedback.selection(context)
          : GlassFeedback.impact(context);
    }

    return GlassPressEffect(
      enabled: active,
      child: Semantics(
        button: true,
        enabled: active,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            enableFeedback: !LiquidTheme.isActive(context),
            splashFactory: LiquidTheme.isActive(context)
                ? NoSplash.splashFactory
                : null,
            onTap: active && onTap != null
                ? () {
                    feedback();
                    onTap!();
                  }
                : null,
            onLongPress: active && onLongPress != null
                ? () {
                    feedback();
                    onLongPress!();
                  }
                : null,
            child: ConstrainedBox(
              constraints: LiquidTheme.isActive(context)
                  ? const BoxConstraints(minHeight: 48, minWidth: 48)
                  : const BoxConstraints(),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme-level adapter for Material buttons, including disabled and keyboard
/// activation states, without replacing their focus or gesture handling.
class LiquidButtonLayer extends StatefulWidget {
  final Set<WidgetState> states;
  final Widget child;
  final bool prominent;
  const LiquidButtonLayer({
    super.key,
    required this.states,
    required this.child,
    this.prominent = false,
  });
  @override
  State<LiquidButtonLayer> createState() => _LiquidButtonLayerState();
}

class _LiquidButtonLayerState extends State<LiquidButtonLayer> {
  Offset? _origin;
  bool _cancelled = false;
  int _feedbackAtPress = -100;

  @override
  void didUpdateWidget(LiquidButtonLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pressed = widget.states.contains(WidgetState.pressed);
    final wasPressed = oldWidget.states.contains(WidgetState.pressed);
    if (pressed && !wasPressed) {
      _feedbackAtPress = GlassFeedback._last;
      if (_origin == null) _cancelled = false;
    } else if (!pressed && wasPressed) {
      // Let the action's own feedback run first, then fill in ordinary buttons.
      // Observing pointer movement also avoids vibrating after a cancelled tap.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_cancelled && GlassFeedback._last == _feedbackAtPress) {
          widget.prominent
              ? GlassFeedback.impact(context)
              : GlassFeedback.selection(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.states.contains(WidgetState.pressed);
    final motion = LiquidTheme.motionOf(context);
    // Material has already resolved the button's per-instance style. Preserve
    // semantic overrides such as destructive red and their foreground colors.
    final buttonMaterial = context.findAncestorWidgetOfExactType<Material>();
    final tint = buttonMaterial?.color ?? Theme.of(context).colorScheme.primary;
    return Listener(
      onPointerDown: (event) {
        _origin = event.position;
        _cancelled = false;
      },
      onPointerMove: (event) {
        if (_origin != null && (event.position - _origin!).distance > 12) {
          _cancelled = true;
        }
      },
      onPointerCancel: (_) {
        _origin = null;
        _cancelled = true;
      },
      onPointerUp: (_) => _origin = null,
      child: AnimatedScale(
        scale: pressed && motion ? .96 : 1,
        duration: motion
            ? Duration(milliseconds: pressed ? 100 : 280)
            : Duration.zero,
        curve: pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.prominent && !widget.states.contains(WidgetState.disabled)
            ? GlassSurface(
                borderRadius: 18,
                tintColor: tint,
                child: widget.child,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: pressed
                      ? Colors.white.withValues(alpha: .14)
                      : Colors.transparent,
                ),
                child: widget.child,
              ),
      ),
    );
  }
}
