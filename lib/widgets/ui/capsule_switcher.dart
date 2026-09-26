import 'package:flutter/material.dart';
import '../../styles/tokens.dart';
import '../../styles/liquid_theme.dart';
import 'liquid_glass.dart';

/// 胶囊选项配置
class CapsuleOption<T> {
  final T value;
  final String label;
  final VoidCallback? onTap; // 点击箭头的回调
  final bool showArrow;

  const CapsuleOption({
    required this.value,
    required this.label,
    this.onTap,
    this.showArrow = false,
  });
}

/// 通用胶囊切换器组件
class CapsuleSwitcher<T> extends StatelessWidget {
  final T selectedValue;
  final List<CapsuleOption<T>> options;
  final ValueChanged<T> onChanged;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Color? selectedTextColor;
  final Color? unselectedTextColor;
  final double height;
  final BorderRadius? borderRadius;

  const CapsuleSwitcher({
    super.key,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.selectedTextColor,
    this.unselectedTextColor,
    this.height = 40,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (LiquidTheme.isActive(context)) return _buildLiquid(context);
    final isDark = BeeTokens.isDark(context);
    final bg = backgroundColor ?? BeeTokens.surfaceCapsule(context);
    final selectedBg =
        selectedBackgroundColor ??
        (isDark ? BeeTokens.primary(context) : Colors.black);
    final selectedFg = selectedTextColor ?? Colors.white;
    final unselectedFg = unselectedTextColor ?? BeeTokens.textPrimary(context);
    final radius = borderRadius ?? BorderRadius.circular(20);

    Widget buildSegment(CapsuleOption<T> option) {
      final selected = selectedValue == option.value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(option.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: height - 6, // 减去padding
            decoration: BoxDecoration(
              color: selected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular((height - 6) / 2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Text(
                  option.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? selectedFg : unselectedFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (option.showArrow && option.onTap != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: option.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: selected ? selectedFg : unselectedFg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Row(
        children: options
            .map((option) => buildSegment(option))
            .expand((widget) => [widget, const SizedBox(width: 4)])
            .take(options.length * 2 - 1) // 移除最后一个SizedBox
            .toList(),
      ),
    );
  }

  Widget _buildLiquid(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    final current = options.indexWhere(
      (option) => option.value == selectedValue,
    );
    final selectedIndex = current < 0 ? 0 : current;
    return GlassSurface(
      borderRadius: 24,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: height < 48 ? 48 : height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / options.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  left: selectedIndex * width,
                  top: 0,
                  bottom: 0,
                  width: width,
                  duration: LiquidTheme.motionOf(context)
                      ? const Duration(milliseconds: 280)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: primary.withValues(alpha: .13),
                      border: Border.all(
                        color: primary.withValues(alpha: .15),
                        width: .7,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: GlassPressable(
                          selectionFeedback: true,
                          onTap: () {
                            if (selectedValue != option.value)
                              onChanged(option.value);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  option.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: option.value == selectedValue
                                            ? primary
                                            : BeeTokens.textSecondary(context),
                                      ),
                                ),
                              ),
                              if (option.showArrow && option.onTap != null)
                                IconButton(
                                  onPressed: option.onTap,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
