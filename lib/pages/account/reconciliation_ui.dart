import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../styles/tokens.dart';
import '../../utils/beijing_time.dart';
import '../../widgets/ui/bee_sheet.dart';

String reconciliationDate(DateTime value, {bool time = false}) => DateFormat(
  time ? 'yyyy-MM-dd HH:mm:ss' : 'yyyy-MM-dd',
).format(beijingTime(value));

/// These forms need visible control boundaries in both appearance modes.
class ReconciliationTheme extends StatelessWidget {
  final Widget child;
  const ReconciliationTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget background(
      BuildContext context,
      Set<WidgetState> states,
      Widget? child,
    ) => child ?? const SizedBox.shrink();
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            disabledBackgroundColor: colors.onSurface.withValues(alpha: .08),
            disabledForegroundColor: colors.onSurface.withValues(alpha: .45),
            side: BorderSide(color: colors.primary.withValues(alpha: .35)),
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: shape,
          ).copyWith(backgroundBuilder: background),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.primary,
            side: BorderSide(color: colors.primary.withValues(alpha: .4)),
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: shape,
          ).copyWith(backgroundBuilder: background),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: colors.primary,
          ).copyWith(backgroundBuilder: background),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: BeeTokens.surfaceInput(context),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outline),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outline.withValues(alpha: .5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.error),
          ),
        ),
      ),
      child: child,
    );
  }
}

class ReconciliationCard extends StatelessWidget {
  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;
  const ReconciliationCard({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? colors.primary : colors.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class ReconciliationField extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final VoidCallback? onTap;
  const ReconciliationField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: BeeTokens.surfaceInput(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(value, style: Theme.of(context).textTheme.bodyLarge),
                    if (hint != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        hint!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReconciliationNotice extends StatelessWidget {
  final String text;
  final bool warning;
  const ReconciliationNotice(this.text, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = warning ? colors.error : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.info_outline : Icons.help_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class ReconciliationHeading extends StatelessWidget {
  final String title;
  final String? description;
  const ReconciliationHeading(this.title, {super.key, this.description});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ],
    ),
  );
}

Future<T?> showReconciliationSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showBeeBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: BeeTokens.surfaceElevated(context),
  builder: (context) => ReconciliationTheme(child: Builder(builder: builder)),
);

class ReconciliationSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget footer;
  const ReconciliationSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height:
          MediaQuery.sizeOf(context).height * .86 -
          MediaQuery.viewInsetsOf(context).bottom,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.all(16), child: footer),
          ],
        ),
      ),
    ),
  );
}

Future<DateTime?> pickReconciliationTime(
  BuildContext context, {
  required String title,
  required DateTime initial,
  DateTime? first,
  DateTime? last,
}) {
  final min = first ?? beijingDate(2000, 1).toUtc();
  final max = last ?? DateTime.now().toUtc();
  var value = beijingTime(
    initial.isBefore(min)
        ? min
        : initial.isAfter(max)
        ? max
        : initial,
  );
  String? error;
  return showReconciliationSheet<DateTime>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) => ReconciliationSheet(
        title: title,
        subtitle: '北京时间',
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                reconciliationDate(value, time: true),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CalendarDatePicker(
                initialDate: DateTime(value.year, value.month, value.day),
                firstDate: DateTime(
                  beijingTime(min).year,
                  beijingTime(min).month,
                  beijingTime(min).day,
                ),
                lastDate: DateTime(
                  beijingTime(max).year,
                  beijingTime(max).month,
                  beijingTime(max).day,
                ),
                onDateChanged: (date) => change(() {
                  value = beijingDate(
                    date.year,
                    date.month,
                    date.day,
                    value.hour,
                    value.minute,
                    value.second,
                  );
                  error = null;
                }),
              ),
              Row(
                children: [
                  for (final part in ['时', '分', '秒']) ...[
                    if (part != '时') const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: part == '时'
                            ? value.hour
                            : part == '分'
                            ? value.minute
                            : value.second,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: part),
                        items: List.generate(
                          part == '时' ? 24 : 60,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(i.toString().padLeft(2, '0')),
                          ),
                        ),
                        onChanged: (v) => change(() {
                          value = beijingDate(
                            value.year,
                            value.month,
                            value.day,
                            part == '时' ? v! : value.hour,
                            part == '分' ? v! : value.minute,
                            part == '秒' ? v! : value.second,
                          );
                          error = null;
                        }),
                      ),
                    ),
                  ],
                ],
              ),
              if (first != null || last != null)
                ReconciliationNotice(
                  '可选范围：${reconciliationDate(min, time: true)} 至 ${reconciliationDate(max, time: true)}',
                ),
              if (error != null) ReconciliationNotice(error!, warning: true),
            ],
          ),
        ),
        footer: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              if (value.isBefore(min) || value.isAfter(max)) {
                change(() => error = '时间超出可选范围，请调整日期或时分秒。');
                return;
              }
              Navigator.pop(context, value.toUtc());
            },
            child: const Text('确认时间'),
          ),
        ),
      ),
    ),
  );
}
