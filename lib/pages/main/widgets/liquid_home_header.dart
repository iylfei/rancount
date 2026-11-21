import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../../providers/budget_providers.dart';
import '../../../styles/tokens.dart';
import '../../../utils/format_utils.dart';
import '../../../widgets/biz/biz.dart';
import '../../../widgets/biz/ledger_picker_sheet.dart';
import '../../../widgets/ui/liquid_glass.dart';
import '../../budget/budget_page.dart';
import '../ledgers_page_new.dart';

/// Presentation only: month navigation and transaction subscriptions stay in HomePage.
class LiquidHomeHeader extends ConsumerWidget {
  const LiquidHomeHeader({
    super.key,
    required this.month,
    required this.isJumping,
    required this.onDateTap,
    required this.onCalendarTap,
    required this.onSearchTap,
    this.onAssistantTap,
  });

  final DateTime month;
  final bool isJumping;
  final VoidCallback onDateTap;
  final VoidCallback onCalendarTap;
  final VoidCallback onSearchTap;
  final VoidCallback? onAssistantTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final ledger = ref.watch(currentLedgerProvider).valueOrNull;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: GlassPressable(
                    onTap: () {
                      if (ledger == null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LedgersPageNew(
                              autoOpenCreateDialog: true,
                            ),
                          ),
                        );
                      } else {
                        showLedgerPicker(context);
                      }
                    },
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.auto_stories_rounded,
                              size: 21,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.homeAppTitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        ledger == null
                                            ? l10n.ledgersNew
                                            : translateLedgerName(
                                                context,
                                                ledger.name,
                                              ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (ledger?.isShared == true) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.handshake_outlined,
                                        size: 14,
                                        color: primary,
                                      ),
                                      Text(
                                        '${ledger!.memberCount}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: primary,
                                        ),
                                      ),
                                    ],
                                    const Icon(
                                      Icons.expand_more_rounded,
                                      size: 17,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (onAssistantTap != null) ...[
                  _HeaderAction(
                    icon: Icons.auto_awesome_outlined,
                    tooltip: l10n.aiChatTitle,
                    onTap: onAssistantTap!,
                  ),
                  const SizedBox(width: 8),
                ],
                _HeaderAction(
                  icon: Icons.calendar_month_outlined,
                  tooltip: l10n.calendarTitle,
                  onTap: onCalendarTap,
                ),
                const SizedBox(width: 8),
                _HeaderAction(
                  icon: Icons.search_rounded,
                  tooltip: l10n.homeSearch,
                  onTap: onSearchTap,
                ),
              ],
            ),
            const SizedBox(height: 10),
            GlassSurface(
              borderRadius: 28,
              prominent: true,
              padding: const EdgeInsets.fromLTRB(18, 10, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GlassPressable(
                        enabled: !isJumping,
                        selectionFeedback: true,
                        borderRadius: 999,
                        onTap: onDateTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: Colors.white.withValues(
                              alpha: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? .12
                                  : .56,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? .20
                                    : .82,
                              ),
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${l10n.homeYear(month.year)} · ${l10n.homeMonth(month.month.toString().padLeft(2, '0'))}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (isJumping)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              else
                                const Icon(Icons.expand_more_rounded, size: 17),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: l10n.homeBalance,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Icon(
                            ref.watch(hideAmountsProvider)
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            key: ValueKey(ref.watch(hideAmountsProvider)),
                            size: 19,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                        onPressed: () {
                          ref.read(hideAmountsProvider.notifier).state =
                              !ref.read(hideAmountsProvider);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _LiquidMonthlySummary(),
                  const _LiquidBudgetSummary(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 42,
          height: 42,
          child: GlassSurface(
            borderRadius: 999,
            prominent: false,
            child: GlassPressable(
              borderRadius: 999,
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      );
}

class _LiquidMonthlySummary extends ConsumerWidget {
  const _LiquidMonthlySummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final params = (
      ledgerId: ref.watch(currentLedgerIdProvider),
      month: ref.watch(selectedMonthProvider),
    );
    ref.watch(monthlyTotalsProvider(params));
    final (income, expense) =
        ref.watch(lastMonthlyTotalsProvider(params)) ?? (0.0, 0.0);
    Widget metric(String title, double amount, Color color, IconData icon) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: AmountText(
                  value: amount,
                  signed: false,
                  decimals: 2,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
        );
    return Row(
      children: [
        metric(
          l10n.homeIncome,
          income,
          BeeTokens.incomeColor(context, ref),
          Icons.south_west_rounded,
        ),
        const SizedBox(width: 12),
        metric(
          l10n.homeExpense,
          expense,
          BeeTokens.expenseColor(context, ref),
          Icons.north_east_rounded,
        ),
        const SizedBox(width: 12),
        metric(
          l10n.homeBalance,
          income - expense,
          Theme.of(context).colorScheme.primary,
          Icons.balance_rounded,
        ),
      ],
    );
  }
}

class _LiquidBudgetSummary extends ConsumerWidget {
  const _LiquidBudgetSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(homeBudgetCardEnabledProvider);
    final usage = ref.watch(budgetOverviewProvider).valueOrNull?.totalBudget;
    if (!enabled || usage == null) return const SizedBox.shrink();
    final color = usage.rate >= 1
        ? Theme.of(context).colorScheme.error
        : usage.rate >= .7
            ? Colors.orange
            : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassPressable(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const BudgetPage())),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.donut_large_rounded, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).budgetUsed,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(usage.rate * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 16, color: color),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage.rate.clamp(0.0, 1.0),
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: .12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
