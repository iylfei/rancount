// Adapted from liquid_glass_renderer 0.2.0-dev.4 (MIT, Copyright 2025 Tim Lehmann for whynotmake.it).
// License: third_party/liquid_glass_renderer-LICENSE.
// Compatibility patch for https://github.com/flutter/flutter/issues/169936.
// Keep this version-specific renderer boundary separate from application widgets.
// This pinned adapter intentionally shares the renderer's private geometry API.
// ignore_for_file: avoid_setters_without_getters, implementation_imports, invalid_use_of_internal_member

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Represents a layer of multiple [LiquidGlass] shapes or
/// [LiquidGlassBlendGroup]s that have shared [LiquidGlassSettings] and will be
/// rendered together.
///
/// If you create a [CompatibleGlassLayer] with one or more [LiquidGlass] or
/// [LiquidGlassBlendGroup] widgets, the liquid glass effect will be rendered
/// where this layer is.
///
/// Make sure not to stack any other widgets between the [CompatibleGlassLayer] and
/// the [LiquidGlass] widgets, otherwise the liquid glass effect will be behind
/// them.
///
/// ## Example
///
/// ```dart
/// Widget build(BuildContext context) {
///   return CompatibleGlassLayer(
///     child: Column(
///       children: [
///         LiquidGlass(
///           shape: LiquidRoundedSuperellipse(
///             borderRadius: 10,
///           ),
///           child: const SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///         const SizedBox(height: 100),
///         LiquidGlassBlendGroup(
///          blend: 20,
///          child: Row(
///             children: [
///               LiquidGlass.grouped(
///                 shape: const LiquidOval(),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///               LiquidGlass.grouped(
///                 shape: const LiquidRoundedSuperellipse(
///                   borderRadius: 20,
///                 ),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///             ],
///           ),
///         ),
///       ],
///     ),
///   );
/// }
class CompatibleGlassLayer extends StatefulWidget {
  /// Creates a new [CompatibleGlassLayer] with the given [child] and [settings].
  const CompatibleGlassLayer({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    this.fake = false,
    this.useBackdropGroup = false,
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [CompatibleGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  /// Whether to replace all liquid glass effects in this layer with
  /// [FakeGlass] effects.
  final bool fake;

  /// Whether to look up the tree for a [BackdropGroup] to use for this layer's
  /// blur.
  ///
  /// If you have multiple [CompatibleGlassLayer]s in a subtree that use the same
  /// background blur, setting this to true can improve performance by sharing
  /// the same backdrop.
  ///
  /// If [fake] is true, this will be ignored, as this widget will already use
  /// a shared backdrop for the fake glass effect.
  ///
  /// Defaults to false.
  final bool useBackdropGroup;

  @override
  State<CompatibleGlassLayer> createState() => _CompatibleGlassLayerState();
}

class _CompatibleGlassLayerState extends State<CompatibleGlassLayer>
    with SingleTickerProviderStateMixin {
  late final GeometryRenderLink _link = GeometryRenderLink();

  late final logger = Logger(LgrLogNames.layer);

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fake || !ImageFilter.isShaderFilterSupported) {
      if (!ImageFilter.isShaderFilterSupported) {
        logger.warning(
          'CompatibleGlassLayer is only supported when using Impeller at the '
          'moment. Falling back to FakeGlass for CompatibleGlassLayer. '
          'To prevent this warning, enable Impeller, or set '
          'CompatibleGlassLayer.fake to true before you use liquid glass widgets '
          'on Skia.',
        );
      }

      return LiquidGlassRenderScope(
        settings: widget.settings,
        useFake: true,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: BackdropGroup(child: widget.child),
        ),
      );
    }

    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: widget.settings,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: ShaderBuilder(
            assetKey: ShaderKeys.liquidGlassRender,
            (context, shader, child) => _RawShapes(
              renderShader: shader,
              backdropKey: widget.useBackdropGroup
                  ? BackdropGroup.of(context)?.backdropKey
                  : null,
              settings: widget.settings,
              link: _link,
              child: child!,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.renderShader,
    required this.backdropKey,
    required this.settings,
    required Widget super.child,
    required this.link,
  });

  final FragmentShader renderShader;
  final BackdropKey? backdropKey;
  final LiquidGlassSettings settings;
  final GeometryRenderLink link;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderCompatibleGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      renderShader: renderShader,
      backdropKey: backdropKey,
      settings: settings,
      link: link,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCompatibleGlassLayer renderObject,
  ) {
    renderObject
      ..link = link
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..backdropKey = backdropKey;
  }
}

class RenderCompatibleGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderCompatibleGlassLayer({
    required super.renderShader,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.link,
  });

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _blurLayerHandle = LayerHandle<BackdropFilterLayer>();
  final _clipPathLayerHandle = LayerHandle<ClipPathLayer>();
  final _shaderClipLayerHandle = LayerHandle<ClipPathLayer>();

  @override
  Size get desiredMatteSize => switch (owner?.rootNode) {
    final RenderView rv => rv.size,
    final RenderBox rb => rb.size,
    _ => Size.zero,
  };

  @override
  Matrix4 get matteTransform => getTransformTo(null);

  @override
  void onTransformChanged() {
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) {
    if (!attached) return;
    final blurLayer = (_blurLayerHandle.layer ??= BackdropFilterLayer())
      ..backdropKey = backdropKey
      ..filter = ImageFilter.blur(
        tileMode: TileMode.mirror,
        sigmaX: settings.effectiveBlur,
        sigmaY: settings.effectiveBlur,
      );

    final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
      // Flutter 3.32.x compares shader filters through a missing native symbol.
      // Clearing first keeps the same compositing layer without that comparison.
      ..filter = null
      ..filter = ImageFilter.shader(renderShader);

    final clipPath = Path();
    for (final geometry in shapes) {
      if (!geometry.$1.attached) continue;

      clipPath.addPath(
        geometry.$2.path,
        Offset.zero,
        matrix4: geometry.$3.storage,
      );
    }
    _clipPathLayerHandle.layer = context
        // First we push the clipped blur layer
        .pushClipPath(
          needsCompositing,
          offset,
          boundingBox,
          clipPath,
          (context, offset) {
            context.pushLayer(blurLayer, (context, offset) {
              // If glass contains child we paint it above blur but below shader
              paintShapeContents(context, offset, shapes, insideGlass: true);
            }, offset);
          },
          oldLayer: _clipPathLayerHandle.layer,
        );
    // The geometry texture alone leaves bright stair steps at curved edges.
    // Clip the final filter with the same antialiased vector path as the blur.
    _shaderClipLayerHandle.layer = context.pushClipPath(
      needsCompositing,
      offset,
      boundingBox,
      clipPath,
      (context, offset) {
        context.pushLayer(shaderLayer, (context, offset) {
          paintShapeContents(context, offset, shapes, insideGlass: false);
        }, offset);
      },
      clipBehavior: Clip.antiAlias,
      oldLayer: _shaderClipLayerHandle.layer,
    );
  }

  @override
  void dispose() {
    _blurLayerHandle.layer = null;
    _shaderHandle.layer = null;
    _clipPathLayerHandle.layer = null;
    _shaderClipLayerHandle.layer = null;
    super.dispose();
  }
}
