import 'package:flutter/material.dart';
import '../../styles/tokens.dart';
import '../../styles/liquid_theme.dart';
import 'liquid_glass.dart';

/// 菜单项类型
enum BeeMenuItemType {
  /// 普通操作项
  action,

  /// 提示信息（禁用状态）
  tip,

  /// 分隔线
  divider,
}

/// 菜单项配置
class BeeMenuItem {
  final String? value;
  final IconData? icon;
  final String? label;
  final BeeMenuItemType type;
  final bool isDanger;

  const BeeMenuItem._({
    this.value,
    this.icon,
    this.label,
    required this.type,
    this.isDanger = false,
  });

  /// 创建普通操作项
  const BeeMenuItem.action({
    required String value,
    required IconData icon,
    required String label,
    bool isDanger = false,
  }) : this._(
         value: value,
         icon: icon,
         label: label,
         type: BeeMenuItemType.action,
         isDanger: isDanger,
       );

  /// 创建提示信息
  const BeeMenuItem.tip({
    required String label,
    IconData icon = Icons.lightbulb_outline,
  }) : this._(icon: icon, label: label, type: BeeMenuItemType.tip);

  /// 创建分隔线
  const BeeMenuItem.divider() : this._(type: BeeMenuItemType.divider);
}

/// 美化的弹出菜单组件
class BeePopupMenu extends StatelessWidget {
  /// 菜单项列表
  final List<BeeMenuItem> items;

  /// 选中回调
  final ValueChanged<String>? onSelected;

  /// 主题色（用于图标背景）
  final Color? primaryColor;

  /// 自定义图标
  final Widget? icon;

  /// 提示文字
  final String? tooltip;

  const BeePopupMenu({
    super.key,
    required this.items,
    this.onSelected,
    this.primaryColor,
    this.icon,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    if (LiquidTheme.isActive(context)) return _liquidMenu(context);
    final isDark = BeeTokens.isDark(context);
    final themeColor = primaryColor ?? Theme.of(context).colorScheme.primary;

    return PopupMenuButton<String>(
      icon:
          icon ?? Icon(Icons.more_vert, color: BeeTokens.textPrimary(context)),
      tooltip: tooltip,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: BeeTokens.surface(context),
      elevation: isDark ? 8 : 4,
      offset: const Offset(0, 8),
      onSelected: onSelected,
      itemBuilder: (context) {
        final List<PopupMenuEntry<String>> entries = [];
        for (final item in items) {
          switch (item.type) {
            case BeeMenuItemType.action:
              entries.add(_buildActionItem(context, item, themeColor));
              break;
            case BeeMenuItemType.tip:
              entries.add(_buildTipItem(context, item));
              break;
            case BeeMenuItemType.divider:
              entries.add(const PopupMenuDivider(height: 1));
              break;
          }
        }
        return entries;
      },
    );
  }

  Widget _liquidMenu(BuildContext context) => Builder(
    builder: (buttonContext) {
      return IconButton(
        icon: icon ?? const Icon(Icons.more_horiz_rounded),
        tooltip: tooltip,
        onPressed: () async {
          final box = buttonContext.findRenderObject() as RenderBox?;
          if (box == null) return;
          final origin = box.localToGlobal(Offset.zero);
          final media = MediaQuery.of(buttonContext);
          final width = (media.size.width - 32).clamp(0.0, 280.0);
          final height = items.fold<double>(
            16,
            (sum, item) =>
                sum + (item.type == BeeMenuItemType.divider ? 9 : 56),
          );
          final left = (origin.dx + box.size.width - width).clamp(
            16.0,
            media.size.width - width - 16,
          );
          final below = origin.dy + box.size.height + 8;
          final top =
              (below + height < media.size.height - media.padding.bottom
                      ? below
                      : origin.dy - height - 8)
                  .clamp(
                    media.padding.top + 8,
                    media.size.height - media.padding.bottom - 64,
                  );
          final value = await showDialog<String>(
            context: buttonContext,
            barrierColor: Colors.black.withValues(alpha: .08),
            builder: (ctx) => Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: width,
                  child: Material(
                    color: Colors.transparent,
                    child: GlassSurface(
                      borderRadius: 24,
                      padding: const EdgeInsets.all(8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              media.size.height -
                              top -
                              media.padding.bottom -
                              16,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final item in items)
                                if (item.type == BeeMenuItemType.divider)
                                  const Divider(height: 9)
                                else
                                  GlassPressable(
                                    enabled:
                                        item.type == BeeMenuItemType.action,
                                    onTap: () => Navigator.pop(ctx, item.value),
                                    selectionFeedback: true,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          if (item.icon != null) ...[
                                            Icon(
                                              item.icon,
                                              size: 21,
                                              color: item.isDanger
                                                  ? Theme.of(
                                                      ctx,
                                                    ).colorScheme.error
                                                  : Theme.of(
                                                      ctx,
                                                    ).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                          Expanded(
                                            child: Text(
                                              item.label ?? '',
                                              style: TextStyle(
                                                color: item.isDanger
                                                    ? Theme.of(
                                                        ctx,
                                                      ).colorScheme.error
                                                    : BeeTokens.textPrimary(
                                                        ctx,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          if (value != null) onSelected?.call(value);
        },
      );
    },
  );

  PopupMenuItem<String> _buildActionItem(
    BuildContext context,
    BeeMenuItem item,
    Color themeColor,
  ) {
    final color = item.isDanger ? Colors.red : themeColor;

    return PopupMenuItem<String>(
      value: item.value,
      height: 48,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Text(
            item.label ?? '',
            style: TextStyle(
              fontSize: 15,
              color: item.isDanger
                  ? Colors.red
                  : BeeTokens.textPrimary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildTipItem(BuildContext context, BeeMenuItem item) {
    return PopupMenuItem<String>(
      value: 'tip',
      enabled: false,
      height: 40,
      child: Row(
        children: [
          Icon(item.icon, size: 16, color: BeeTokens.textTertiary(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.label ?? '',
              style: TextStyle(
                fontSize: 12,
                color: BeeTokens.textTertiary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
