import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../styles/tokens.dart';
import '../../../widgets/biz/amount_text.dart';
import 'liquid_main_section.dart';

class LiquidAnalyticsSummary extends ConsumerWidget {
  const LiquidAnalyticsSummary({
    super.key,
    required this.scope,
    required this.type,
    required this.total,
    required this.average,
  });
  final String scope;
  final String type;
  final double total;
  final double average;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title = type == 'balance'
        ? l10n.analyticsBalance
        : type == 'expense'
            ? l10n.analyticsExpense
            : l10n.analyticsIncome;
    final avgLabel = scope == 'year'
        ? l10n.analyticsMonthlyAvg
        : scope == 'all'
            ? l10n.analyticsOverallAvg
            : l10n.analyticsDailyAvg;
    final color = type == 'expense'
        ? BeeTokens.expenseColor(context, ref)
        : type == 'income'
            ? BeeTokens.incomeColor(context, ref)
            : Theme.of(context).colorScheme.primary;
    return LiquidContentCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  type == 'balance'
                      ? Icons.balance_rounded
                      : type == 'expense'
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                  size: 17,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.analyticsTotal(title),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(
              value: total,
              signed: false,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l10n.analyticsAverage(avgLabel),
                style: TextStyle(
                  fontSize: 12,
                  color: BeeTokens.textSecondary(context),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: AmountText(
                  value: average,
                  signed: false,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
