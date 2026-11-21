import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as renderer;
import '../../styles/liquid_theme.dart';
import 'compatible_glass_layer.dart';

/// Authentic iOS-style Liquid Glass surface:
/// - Semi-transparent optical body with live backdrop blur & vibrancy saturation lift
/// - Subtle perimeter refraction & chromatic dispersion via [CompatibleGlassLayer]
/// - Directional specular highlight rim + inner top caustic sheen
/// - Dual-layer soft floating elevation shadow
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
    final pauseListenable = _GlassTransitionScope.listenableOf(context);
    final padded = Padding(padding: padding, child: child);
    final content = prominent && !nested ? _GlassScope(child: padded) : padded;
    if (!appearance.enabled) return Padding(padding: margin, child: content);

    final highContrast = MediaQuery.highContrastOf(context);
    final isCapsule = borderRadius >= 100;
    final shape = isCapsule
        ? const renderer.LiquidRoundedRectangle(borderRadius: 999)
        : renderer.LiquidRoundedSuperellipse(borderRadius: borderRadius);

    final isTinted = tintColor != null;
    final tint =
        tintColor ?? (dark ? const Color(0xFF1C293D) : const Color(0xFFFFFFFF));
    // Keep tinted glass genuinely translucent so backdrop blur & edge refraction remain visible.
    final resolvedAlpha =
        tintOpacity ??
        (isTinted
            ? (dark ? .68 : .74)
            : (dark ? .30 : .32));

    final settings = renderer.LiquidGlassSettings(
      thickness: prominent ? 22 : 12,
      blur: prominent ? 15 : 9,
      refractiveIndex: prominent ? 1.42 : 1.18,
      chromaticAberration: prominent ? .08 : .02,
      lightAngle: 0.78,
      lightIntensity: dark ? .52 : .66,
      ambientStrength: dark ? .12 : .16,
      saturation: prominent ? 1.52 : 1.25,
      glassColor: tint.withValues(alpha: resolvedAlpha),
    );

    Widget material;
    if (highContrast) {
      material = DecoratedBox(
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    } else if (nested || !prominent) {
      material = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isTinted
                ? [
                    tint.withValues(alpha: dark ? .76 : .82),
                    tint.withValues(alpha: dark ? .62 : .70),
                  ]
                : [
                    tint.withValues(alpha: dark ? .38 : .64),
                    tint.withValues(alpha: dark ? .22 : .42),
                  ],
          ),
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
        pauseListenable: pauseListenable,
        fallbackRadius: borderRadius,
        child: renderer.LiquidGlass(
          shape: shape,
          child: const SizedBox.expand(),
        ),
      );
    }

    // Keep interactive controls in the normal Flutter paint tree so shader/geometry
    // never hides content or semantics.
    final surface = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(child: IgnorePointer(child: material)),
        ),
        if (!highContrast)
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpecularGlassRimPainter(
                    borderRadius: borderRadius,
                    dark: dark,
                    tinted: isTinted,
                    prominent: prominent,
                  ),
                ),
              ),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      ],
    );

    final shadowBase = isTinted
        ? tint
        : (dark ? const Color(0xFF040A14) : const Color(0xFF14315A));

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: shadowBase.withValues(
                alpha: isTinted
                    ? (dark ? .34 : .26)
                    : (dark ? .28 : .10),
              ),
              blurRadius: prominent ? 26 : 18,
              spreadRadius: -3,
              offset: Offset(0, prominent ? 10 : 6),
            ),
            BoxShadow(
              color: shadowBase.withValues(
                alpha: isTinted
                    ? (dark ? .18 : .14)
                    : (dark ? .18 : .05),
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: surface,
      ),
    );
  }
}

/// Paints an iOS-style directional specular rim and subtle inner caustic sheen.
class _SpecularGlassRimPainter extends CustomPainter {
  final double borderRadius;
  final bool dark;
  final bool tinted;
  final bool prominent;

  const _SpecularGlassRimPainter({
    required this.borderRadius,
    required this.dark,
    required this.tinted,
    required this.prominent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final maxR = math.min(size.width, size.height) / 2;
    final r = borderRadius.clamp(0.0, maxR);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    // 1. Subtle top-edge inner glass reflection sheen
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(
            alpha: tinted ? (dark ? .22 : .30) : (dark ? .14 : .36),
          ),
          Colors.white.withValues(alpha: .0),
        ],
        stops: const [0.0, 0.36],
      ).createShader(rect);
    canvas.drawRRect(rrect, sheenPaint);

    // 2. Directional mirror-like rim highlight (strong top-left + subtle bottom-right bounce)
    final strokeWidth = prominent ? 1.15 : 0.9;
    final rimRect = rect.deflate(strokeWidth / 2);
    final rimRRect = RRect.fromRectAndRadius(
      rimRect,
      Radius.circular(math.max(0.0, r - strokeWidth / 2)),
    );
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [
                Colors.white.withValues(alpha: tinted ? .52 : .44),
                Colors.white.withValues(alpha: .10),
                Colors.white.withValues(alpha: .06),
                Colors.white.withValues(alpha: tinted ? .30 : .24),
              ]
            : [
                Colors.white.withValues(alpha: tinted ? .74 : .92),
                Colors.white.withValues(alpha: tinted ? .24 : .36),
                Colors.white.withValues(alpha: tinted ? .14 : .22),
                Colors.white.withValues(alpha: tinted ? .46 : .68),
              ],
        stops: const [0.0, 0.34, 0.68, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rimRRect, rimPaint);
  }

  @override
  bool shouldRepaint(_SpecularGlassRimPainter old) =>
      old.borderRadius != borderRadius ||
      old.dark != dark ||
      old.tinted != tinted ||
      old.prominent != prominent;
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({required super.child});
  @override
  bool updateShouldNotify(_GlassScope oldWidget) => false;
}

class _GlassTransitionScope extends InheritedWidget {
  final ValueListenable<bool> listenable;
  const _GlassTransitionScope({
    required this.listenable,
    required super.child,
  });

  static ValueListenable<bool>? listenableOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<_GlassTransitionScope>()
          ?.listenable;

  @override
  bool updateShouldNotify(_GlassTransitionScope oldWidget) =>
      oldWidget.listenable != listenable;
}

/// Signals [RenderCompatibleGlassLayer] directly via [ValueNotifier] to pause
/// heavy geometry/shader work while a route slides, with zero widget rebuilds.
class GlassTransitionBarrier extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const GlassTransitionBarrier({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  State<GlassTransitionBarrier> createState() => _GlassTransitionBarrierState();
}

class _GlassTransitionBarrierState extends State<GlassTransitionBarrier> {
  late final ValueNotifier<bool> _animating = ValueNotifier<bool>(_isActive);

  bool get _isActive =>
      widget.animation.status == AnimationStatus.forward ||
      widget.animation.status == AnimationStatus.reverse ||
      widget.secondaryAnimation.status == AnimationStatus.forward ||
      widget.secondaryAnimation.status == AnimationStatus.reverse;

  void _onStatus(AnimationStatus _) {
    final next = _isActive;
    if (_animating.value != next) {
      _animating.value = next;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
    widget.secondaryAnimation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(GlassTransitionBarrier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      oldWidget.secondaryAnimation.removeStatusListener(_onStatus);
      widget.secondaryAnimation.addStatusListener(_onStatus);
    }
    _animating.value = _isActive;
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    widget.secondaryAnimation.removeStatusListener(_onStatus);
    _animating.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _GlassTransitionScope(listenable: _animating, child: widget.child);
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
      child: CustomPaint(
        painter: _AtmosphericBackdropPainter(dark: dark),
        child: child,
      ),
    );
  }
}

/// Paints an airy iOS-inspired atmospheric canvas with soft luminance blooms
/// so translucent Liquid Glass capsules visibly blur, saturate and refract light.
class _AtmosphericBackdropPainter extends CustomPainter {
  final bool dark;
  const _AtmosphericBackdropPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [
                Color(0xFF0B1320),
                Color(0xFF132238),
                Color(0xFF0A101B),
              ]
            : const [
                Color(0xFFEEF4FC),
                Color(0xFFE3EEFD),
                Color(0xFFF4F7FD),
              ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    void drawBloom(Offset centerFactor, double radiusFactor, Color color) {
      final center = Offset(
        size.width * centerFactor.dx,
        size.height * centerFactor.dy,
      );
      final radius = math.max(size.width, size.height) * radiusFactor;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    if (dark) {
      drawBloom(const Offset(0.15, 0.12), 0.52, const Color(0x382A6DF4));
      drawBloom(const Offset(0.88, 0.28), 0.48, const Color(0x2E5E5CE6));
      drawBloom(const Offset(0.50, 0.90), 0.50, const Color(0x241B87A8));
    } else {
      drawBloom(const Offset(0.12, 0.08), 0.56, const Color(0x6692C5FF));
      drawBloom(const Offset(0.90, 0.24), 0.50, const Color(0x52B9C4FF));
      drawBloom(const Offset(0.45, 0.92), 0.52, const Color(0x4D9CE5FF));
    }
  }

  @override
  bool shouldRepaint(_AtmosphericBackdropPainter old) => old.dark != dark;
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
/// existing gesture recognizers. Adds springy iOS squash-and-bounce + live
/// finger-tracking specular glow.
class GlassPressEffect extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;
  final double borderRadius;
  const GlassPressEffect({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = .95,
    this.borderRadius = 28,
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

  void _updateLight(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      final local = box.globalToLocal(globalPos);
      _light = Alignment(
        (local.dx / box.size.width * 2 - 1).clamp(-1, 1),
        (local.dy / box.size.height * 2 - 1).clamp(-1, 1),
      );
    }
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
        _updateLight(event.position);
        setState(() => _pressed = true);
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer || _origin == null) return;
        if ((event.position - _origin!).distance > 16) {
          _release();
        } else if (_pressed) {
          _updateLight(event.position);
          setState(() {});
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
            ? Duration(milliseconds: _pressed ? 95 : 340)
            : Duration.zero,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _pressed ? 1.0 : 0.0,
                  duration: motion
                      ? Duration(milliseconds: _pressed ? 80 : 220)
                      : Duration.zero,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      gradient: RadialGradient(
                        center: _light,
                        radius: 1.05,
                        colors: [
                          Colors.white.withValues(alpha: .32),
                          Colors.white.withValues(alpha: .04),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
  final double borderRadius;
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selectionFeedback = false,
    this.borderRadius = 28,
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
      borderRadius: borderRadius,
      child: Semantics(
        button: true,
        enabled: active,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
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

/// Theme-level adapter for Material buttons: renders authentic iOS capsule
/// Liquid Glass pills with live specular sheen, backdrop refraction, and
/// springy press physics while preserving Material semantics & focus.
class LiquidButtonLayer extends StatefulWidget {
  final Set<WidgetState> states;
  final Widget child;
  final bool prominent;
  final bool outlined;
  const LiquidButtonLayer({
    super.key,
    required this.states,
    required this.child,
    this.prominent = false,
    this.outlined = false,
  });
  @override
  State<LiquidButtonLayer> createState() => _LiquidButtonLayerState();
}

class _LiquidButtonLayerState extends State<LiquidButtonLayer> {
  Offset? _origin;
  bool _cancelled = false;
  int _feedbackAtPress = -100;
  Alignment _light = Alignment.center;

  void _updateLight(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      final local = box.globalToLocal(globalPos);
      _light = Alignment(
        (local.dx / box.size.width * 2 - 1).clamp(-1, 1),
        (local.dy / box.size.height * 2 - 1).clamp(-1, 1),
      );
    }
  }

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
    final disabled = widget.states.contains(WidgetState.disabled);
    final motion = LiquidTheme.motionOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Material has already resolved the button's per-instance style. Preserve
    // semantic overrides such as destructive red and their foreground colors.
    final buttonMaterial = context.findAncestorWidgetOfExactType<Material>();
    final resolvedBg = buttonMaterial?.color;
    final hasCustomTint =
        resolvedBg != null && resolvedBg.a > 0.01 && resolvedBg != Colors.transparent;
    final tint = hasCustomTint
        ? resolvedBg
        : Theme.of(context).colorScheme.primary;

    Widget content = widget.child;
    if (!disabled && (widget.prominent || widget.outlined)) {
      content = GlassSurface(
        borderRadius: 999,
        prominent: true,
        tintColor: widget.prominent ? tint : null,
        tintOpacity: widget.prominent
            ? (dark ? .68 : .76)
            : (dark ? .26 : .34),
        child: content,
      );
    } else {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: pressed
              ? Colors.white.withValues(alpha: dark ? .14 : .32)
              : Colors.transparent,
        ),
        child: content,
      );
    }

    return Listener(
      onPointerDown: (event) {
        _origin = event.position;
        _cancelled = false;
        _updateLight(event.position);
      },
      onPointerMove: (event) {
        if (_origin != null && (event.position - _origin!).distance > 16) {
          _cancelled = true;
        } else if (pressed) {
          _updateLight(event.position);
          if (mounted) setState(() {});
        }
      },
      onPointerCancel: (_) {
        _origin = null;
        _cancelled = true;
      },
      onPointerUp: (_) => _origin = null,
      child: AnimatedScale(
        scale: pressed && motion ? .945 : 1,
        duration: motion
            ? Duration(milliseconds: pressed ? 95 : 340)
            : Duration.zero,
        curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            content,
            if (!disabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: pressed ? 1.0 : 0.0,
                    duration: motion
                        ? Duration(milliseconds: pressed ? 75 : 200)
                        : Duration.zero,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: RadialGradient(
                          center: _light,
                          radius: 1.05,
                          colors: [
                            Colors.white.withValues(alpha: .34),
                            Colors.white.withValues(alpha: .04),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
