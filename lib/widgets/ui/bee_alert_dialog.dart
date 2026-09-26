import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../styles/liquid_theme.dart';
import 'liquid_glass.dart';

/// Retains Material dialog contracts in classic mode and the same actions and
/// focus traversal in glass mode. Content stays above the refracted backdrop.
class BeeAlertDialog extends AlertDialog {
  const BeeAlertDialog({
    super.key,
    super.icon,
    super.iconPadding,
    super.iconColor,
    super.title,
    super.titlePadding,
    super.titleTextStyle,
    super.content,
    super.contentPadding,
    super.contentTextStyle,
    super.actions,
    super.actionsPadding,
    super.actionsAlignment,
    super.actionsOverflowAlignment,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing,
    super.buttonPadding,
    super.backgroundColor,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.semanticLabel,
    super.insetPadding,
    super.clipBehavior,
    super.shape,
    super.alignment,
    super.scrollable,
  });

  @override
  Widget build(BuildContext context) {
    if (!LiquidTheme.isActive(context)) return super.build(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final availableHeight = math.max(
      120.0,
      media.size.height -
          media.viewInsets.vertical -
          media.padding.vertical -
          64,
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon != null)
          Padding(
            padding: iconPadding ?? const EdgeInsets.only(top: 24),
            child: IconTheme(
              data: IconThemeData(
                color: iconColor ?? theme.colorScheme.primary,
              ),
              child: icon!,
            ),
          ),
        if (title != null)
          Padding(
            padding: titlePadding ?? const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: DefaultTextStyle(
              style: titleTextStyle ?? theme.dialogTheme.titleTextStyle!,
              child: title!,
            ),
          ),
        if (content != null)
          Flexible(
            child: Padding(
              padding:
                  contentPadding ??
                  EdgeInsets.fromLTRB(24, title == null ? 24 : 8, 24, 20),
              child: DefaultTextStyle(
                style: contentTextStyle ?? theme.dialogTheme.contentTextStyle!,
                child: scrollable
                    ? SingleChildScrollView(child: content!)
                    : content!,
              ),
            ),
          ),
        if (actions != null && actions!.isNotEmpty)
          Padding(
            padding: actionsPadding ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OverflowBar(
              alignment: actionsAlignment ?? MainAxisAlignment.end,
              overflowAlignment:
                  actionsOverflowAlignment ?? OverflowBarAlignment.end,
              overflowDirection:
                  actionsOverflowDirection ?? VerticalDirection.down,
              spacing: 8,
              overflowSpacing: actionsOverflowButtonSpacing ?? 8,
              children: actions!,
            ),
          ),
      ],
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      alignment: alignment,
      child: Semantics(
        namesRoute: true,
        scopesRoute: true,
        label:
            semanticLabel ?? MaterialLocalizations.of(context).alertDialogLabel,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: availableHeight,
            maxWidth: 520,
          ),
          child: SizedBox(
            width: math.min(520, media.size.width - 48),
            child: GlassSurface(
              borderRadius: 28,
              tintOpacity: theme.brightness == Brightness.dark ? .52 : .82,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
