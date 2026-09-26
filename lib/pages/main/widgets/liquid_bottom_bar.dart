import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../styles/liquid_theme.dart';
import '../../../widgets/ui/ui.dart';

class LiquidBottomBar extends StatelessWidget {
  const LiquidBottomBar({
    super.key,
    required this.currentIndex,
    required this.avatarPath,
    required this.centerButtonKey,
    required this.onTabTap,
    required this.onCenterTap,
    required this.onCenterLongPressStart,
    required this.onCenterLongPressMoveUpdate,
    required this.onCenterLongPressEnd,
  });

  final int currentIndex;
  final String? avatarPath;
  final GlobalKey centerButtonKey;
  final ValueChanged<int> onTabTap;
  final VoidCallback onCenterTap;
  final GestureLongPressStartCallback onCenterLongPressStart;
  final GestureLongPressMoveUpdateCallback onCenterLongPressMoveUpdate;
  final GestureLongPressEndCallback onCenterLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final activeSlot = currentIndex > 1 ? currentIndex + 1 : currentIndex;
    final animate =
        LiquidTheme.of(context).animationsEnabled &&
        !MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewPaddingOf(context).bottom + 12,
      ),
      child: GlassSurface(
        borderRadius: 32,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth / 5;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: animate
                        ? const Duration(milliseconds: 320)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    left: activeSlot * cellWidth + 5,
                    top: 6,
                    width: cellWidth - 10,
                    height: 52,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: primary.withValues(alpha: .12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tab(
                        context,
                        0,
                        l10n.tabHome,
                        Icons.receipt_long_outlined,
                        Icons.receipt_long_rounded,
                      ),
                      _tab(
                        context,
                        1,
                        l10n.tabInsights,
                        Icons.donut_large_outlined,
                        Icons.donut_large_rounded,
                      ),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: l10n.tabRecord,
                          child: GlassPressEffect(
                            child: GestureDetector(
                              key: centerButtonKey,
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                GlassFeedback.impact(context);
                                onCenterTap();
                              },
                              onLongPressStart: (details) {
                                GlassFeedback.impact(context);
                                onCenterLongPressStart(details);
                              },
                              onLongPressMoveUpdate:
                                  onCenterLongPressMoveUpdate,
                              onLongPressEnd: onCenterLongPressEnd,
                              child: Center(
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .55,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withValues(alpha: .24),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.add_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    size: 29,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _tab(
                        context,
                        2,
                        l10n.tabAssets,
                        Icons.account_balance_wallet_outlined,
                        Icons.account_balance_wallet_rounded,
                      ),
                      _tab(
                        context,
                        3,
                        l10n.tabMine,
                        Icons.person_outline_rounded,
                        Icons.person_rounded,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData selectedIcon,
  ) {
    final selected = currentIndex == index;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    Widget glyph = Icon(selected ? selectedIcon : icon, size: 23, color: color);
    if (index == 3) {
      if (avatarPath != null) {
        glyph = Container(
          width: 25,
          height: 25,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? color : Colors.transparent),
          ),
          child: ClipOval(
            child: Image.file(
              File(avatarPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(selectedIcon, color: color, size: 21),
            ),
          ),
        );
      }
      glyph = FeatureDot(
        anchor: 'tab_mine',
        offset: const Offset(-2, 0),
        child: glyph,
      );
    }
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: GlassPressable(
          selectionFeedback: true,
          onTap: () => onTabTap(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph,
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
