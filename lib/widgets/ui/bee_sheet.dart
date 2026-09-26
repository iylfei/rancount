import 'package:flutter/material.dart';
import '../../styles/liquid_theme.dart';
import 'liquid_glass.dart';

/// Preserves route results, keyboard insets, drag and dismissal contracts.
Future<T?> showBeeBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9 / 16,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  final liquid = LiquidTheme.isActive(context);
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => liquid
        ? GlassSurface(borderRadius: 28, child: builder(context))
        : builder(context),
    backgroundColor: liquid ? Colors.transparent : backgroundColor,
    barrierLabel: barrierLabel,
    elevation: liquid ? 0 : elevation,
    shape: liquid
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          )
        : shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: liquid ? false : showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: liquid && !LiquidTheme.motionOf(context)
        ? AnimationStyle.noAnimation
        : sheetAnimationStyle,
    requestFocus: requestFocus,
  );
}
