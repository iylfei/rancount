import 'package:flutter/material.dart';
import '../../styles/tokens.dart';
import '../../styles/liquid_theme.dart';
import '../ui/liquid_glass.dart';

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin; // 新增 margin 参数
  final Color? borderColor;
  final double? borderWidth;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BeeDimens.p12),
    this.margin = const EdgeInsets.symmetric(horizontal: BeeDimens.p12), // 默认值
    this.borderColor,
    this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (LiquidTheme.isActive(context)) {
      final card = GlassSurface(
        prominent: false,
        padding: padding,
        margin: borderColor == null ? margin : EdgeInsets.zero,
        child: child,
      );
      if (borderColor == null) return card;
      return Padding(
        padding: margin,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: borderColor!,
              width: borderWidth ?? 1.5,
            ),
          ),
          child: card,
        ),
      );
    }
    final isDark = BeeTokens.isDark(context);
    final effectiveBorderWidth = borderColor != null
        ? (borderWidth ?? 2.0)
        : BeeTokens.cardOuterBorderWidth(context);
    final effectiveBorderColor =
        borderColor ?? BeeTokens.cardOuterBorderColor(context);

    return Container(
      margin: margin, // 使用传入的 margin
      decoration: BoxDecoration(
        color: BeeTokens.surface(context), // ⭐ 使用 Token
        borderRadius: BorderRadius.circular(BeeDimens.radius12),
        border: effectiveBorderWidth > 0
            ? Border.all(
                color: effectiveBorderColor, // ⭐ 使用卡片边框 Token
                width: effectiveBorderWidth,
              )
            : null,
        boxShadow: isDark ? null : BeeShadows.card,  // ⭐ 暗黑模式：无阴影，亮色模式：有阴影
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
