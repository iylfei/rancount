import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../pages/account/monthly_repayments_page.dart';
import '../../pages/account/repayment_plan_sheet.dart';
import '../../providers/repayment_providers.dart';
import '../../services/billing/repayment_schedule.dart';
import '../../utils/beijing_time.dart';
import 'amount_text.dart';

class RepaymentSummary extends ConsumerWidget {
  final Account? account;
  const RepaymentSummary({super.key, this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = beijingNow();
    final month = account == null
        ? ref.watch(repaymentSummaryMonthProvider)
        : DateTime(now.year, now.month);
    final data = ref.watch(monthlyRepaymentsProvider(repaymentMonthKey(month)));
    final nextMonth = month.year != now.year || month.month != now.month;
    final label = account == null
        ? repaymentLabel(
            context,
            nextMonth ? '下月待还款' : '本月待还款',
            nextMonth ? 'Due next month' : 'Due this month',
          )
        : repaymentLabel(context, '月度还款计划', 'Monthly repayment plan');
    final items = data.valueOrNull
        ?.where((item) => account == null || item.accountId == account!.id)
        .toList();
    final totals = <String, double>{};
    for (final item in items ?? <MonthlyRepayment>[]) {
      totals.update(
        item.currency,
        (v) => v + item.remaining,
        ifAbsent: () => item.remaining,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MonthlyRepaymentsPage(
            initialMonth: month,
            accountId: account?.id,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            if (data.hasError)
              Text(
                repaymentLabel(context, '计划读取失败', 'Plan unavailable'),
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (items == null)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (items.isEmpty)
              Text(
                repaymentLabel(context, '设置计划', 'Set plan'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              )
            else
              for (final entry in totals.entries)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AmountText(
                    value: entry.value,
                    signed: false,
                    showCurrency: true,
                    currencyCode: entry.key,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            const SizedBox(height: 3),
            Text(
              repaymentLabel(
                context,
                '${month.month}月 · 查看',
                '${month.month} · View',
              ),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
