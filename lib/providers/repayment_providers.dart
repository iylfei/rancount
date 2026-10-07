import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/billing/repayment_service.dart';

import '../data/db.dart';
import '../services/billing/repayment_schedule.dart';
import '../utils/account_type_utils.dart';
import '../utils/beijing_time.dart';
import 'database_providers.dart';
import 'statistics_providers.dart';

bool canPlanRepayments(Account account, {double? balance}) =>
    isLiabilityType(account.type) ||
    account.creditLimit != null ||
    (balance != null && balance < 0) ||
    account.repaymentSchedule != null;

final monthlyRepaymentsProvider = StreamProvider.autoDispose
    .family<List<MonthlyRepayment>, String>(
      (ref, key) => watchMonthlyRepayments(
        ref.watch(databaseProvider),
        repaymentMonthFromKey(key),
      ),
    );

/// Prefer this month; only a fully settled configured month advances to next month.
final repaymentSummaryMonthProvider = Provider<DateTime>((ref) {
  ref.watch(statsRefreshProvider);
  final now = beijingNow();
  final current = DateTime(now.year, now.month);
  final items = ref
      .watch(monthlyRepaymentsProvider(repaymentMonthKey(current)))
      .valueOrNull;
  if (items != null &&
      items.isNotEmpty &&
      items.every((item) => item.remaining < .005)) {
    return DateTime(current.year, current.month + 1);
  }
  return current;
});

Future<void> updateRepaymentSchedule(
  WidgetRef ref,
  int accountId,
  RepaymentSchedule Function(RepaymentSchedule) update,
) async {
  await editRepaymentSchedule(ref.read(repositoryProvider), accountId, update);
  ref.read(statsRefreshProvider.notifier).state++;
}
