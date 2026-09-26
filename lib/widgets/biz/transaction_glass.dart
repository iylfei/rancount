import 'package:flutter/material.dart';

import '../../styles/liquid_theme.dart';
import '../ui/liquid_glass.dart';

/// Shared presentation for transaction flows; business widgets keep their
/// original gesture recognizers and form state.
class TransactionScaffold extends StatelessWidget {
  const TransactionScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final liquid = LiquidTheme.isActive(context);
    final bar = appBar;
    final scaffold = Scaffold(
      backgroundColor: liquid ? Colors.transparent : backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: liquid && bar != null
          ? PreferredSize(
              preferredSize: bar.preferredSize,
              child: GlassSurface(
                borderRadius: 0,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    appBarTheme: Theme.of(context).appBarTheme.copyWith(
                          backgroundColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                        ),
                  ),
                  child: bar,
                ),
              ),
            )
          : bar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
    return liquid ? LiquidBackdrop(child: scaffold) : scaffold;
  }
}

class TransactionPanel extends StatelessWidget {
  const TransactionPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.decoration,
    this.width,
    this.height,
    this.borderRadius = 24,
    this.prominent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxDecoration? decoration;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context)) {
      return Container(
        width: width,
        height: height,
        padding: padding,
        margin: margin,
        decoration: decoration,
        child: child,
      );
    }
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: SizedBox(
        width: width,
        height: height,
        child: GlassSurface(
          borderRadius: borderRadius,
          padding: padding ?? EdgeInsets.zero,
          prominent: prominent,
          child: child,
        ),
      ),
    );
  }
}

Color transactionPrimary(BuildContext context, Color classic) =>
    LiquidTheme.isActive(context)
        ? Theme.of(context).colorScheme.primary
        : classic;

InputBorder transactionInputBorder(BuildContext context) =>
    LiquidTheme.isActive(context)
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          )
        : const OutlineInputBorder();

Widget transactionAmountFit(BuildContext context, Widget child) =>
    LiquidTheme.isActive(context)
        ? Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: child,
            ),
          )
        : child;

class TransactionGlass extends StatelessWidget {
  const TransactionGlass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 24,
    this.prominent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool prominent;

  @override
  Widget build(BuildContext context) => LiquidTheme.isActive(context)
      ? GlassSurface(
          borderRadius: borderRadius,
          padding: padding,
          prominent: prominent,
          child: child,
        )
      : child;
}

class TransactionCard extends StatelessWidget {
  const TransactionCard({super.key, required this.child, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => LiquidTheme.isActive(context)
      ? TransactionPanel(margin: margin, child: child)
      : Card(margin: margin, child: child);
}

/// Key caps retain the existing InkWell, including double-tap/long-press maths.
class TransactionKeySurface extends StatelessWidget {
  const TransactionKeySurface({
    super.key,
    required this.child,
    required this.color,
    required this.borderRadius,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context)) {
      return Material(color: color, borderRadius: borderRadius, child: child);
    }
    final primary = Theme.of(context).colorScheme.primary;
    final accented = color == primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: accented
                ? [primary.withValues(alpha: .88), primary]
                : [
                    Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: .76),
                    Theme.of(context).colorScheme.surface.withValues(alpha: .4),
                  ],
          ),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .07),
          ),
        ),
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }
}
