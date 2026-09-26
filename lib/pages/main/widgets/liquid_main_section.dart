import 'package:flutter/material.dart';

import '../../../styles/liquid_theme.dart';
import '../../../widgets/ui/liquid_glass.dart';

class LiquidMainFilter extends StatelessWidget {
  const LiquidMainFilter({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context)) {
      return InkWell(onTap: onTap, child: child);
    }
    return GlassPressable(
      onTap: onTap,
      selectionFeedback: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
        ),
        child: child,
      ),
    );
  }
}

/// Quiet content surfaces keep charts and amounts crisp beneath glass controls.
class LiquidContentCard extends StatelessWidget {
  const LiquidContentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context)) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1D2736).withValues(alpha: .88)
            : Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: .10) : Colors.white,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF233A5D).withValues(alpha: dark ? .06 : .035),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class LiquidMainSectionTitle extends StatelessWidget {
  const LiquidMainSectionTitle({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: .3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
