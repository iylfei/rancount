import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pages/transaction/reimbursement_page.dart';
import '../../providers.dart';
import '../../styles/liquid_theme.dart';
import '../../styles/tokens.dart';
import '../ui/liquid_glass.dart';

/// Independent pending reimbursement summary strip for Home / Assets / Analytics.
class ReimbursementBanner extends ConsumerWidget {
  final bool showWhenEmpty;
  final EdgeInsetsGeometry margin;

  const ReimbursementBanner({
    super.key,
    this.showWhenEmpty = false,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final summary = ref.watch(reimbursementSummaryProvider(ledgerId)).valueOrNull;
    if (summary == null) return const SizedBox.shrink();
    if (!showWhenEmpty && summary.pendingCount == 0) {
      return const SizedBox.shrink();
    }

    final hideAmounts = ref.watch(hideAmountsProvider);
    final liquid = LiquidTheme.isActive(context);
    final accent = Colors.orange.shade700;
    final hasPending = summary.pendingCount > 0;
    final amountText = hideAmounts
        ? '****'
        : '¥${summary.totalPendingNative.toStringAsFixed(2)}';

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (hasPending ? accent : Theme.of(context).colorScheme.primary)
                  .withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: hasPending ? accent : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPending
                      ? '待报销款 · ${summary.pendingCount} 笔未到账'
                      : '待报销款（已全部结清）',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '独立统计，不计入真实收支',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BeeTokens.textTertiary(context),
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
          Text(
            amountText,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hasPending ? accent : BeeTokens.textSecondary(context),
                ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: BeeTokens.textTertiary(context),
          ),
        ],
      ),
    );

    final tap = InkWell(
      borderRadius: BorderRadius.circular(liquid ? 22 : 14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReimbursementPage()),
      ),
      child: row,
    );

    if (liquid) {
      return Padding(
        padding: margin,
        child: GlassPressEffect(
          child: GlassSurface(
            borderRadius: 22,
            prominent: true,
            child: tap,
          ),
        ),
      );
    }

    return Padding(
      padding: margin,
      child: Material(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BeeTokens.border(context)),
          ),
          child: tap,
        ),
      ),
    );
  }
}
