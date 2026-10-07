import 'package:drift/drift.dart' as drift;

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../utils/beijing_time.dart';
import 'repayment_schedule.dart';

Stream<List<MonthlyRepayment>> watchMonthlyRepayments(
  BeeDatabase db,
  DateTime month,
) {
  final key = repaymentMonthKey(month);
  final start = beijingDate(month.year, month.month);
  final end = beijingDate(month.year, month.month + 1);
  return db
      .customSelect(
        '''
    SELECT a.id, a.name, a.currency, a.repayment_schedule,
           COALESCE(SUM(t.amount), 0.0) AS transferred
    FROM accounts a LEFT JOIN transactions t
      ON t.to_account_id = a.id AND t.type = 'transfer' AND t.amount > 0
      AND (t.account_id IS NULL OR t.account_id != a.id)
      AND t.happened_at >= ? AND t.happened_at < ?
      AND UPPER(COALESCE(t.currency_code, a.currency)) = UPPER(a.currency)
    WHERE a.repayment_schedule IS NOT NULL
    GROUP BY a.id
  ''',
        variables: [
          drift.Variable.withInt(start.millisecondsSinceEpoch ~/ 1000),
          drift.Variable.withInt(end.millisecondsSinceEpoch ~/ 1000),
        ],
        readsFrom: {db.accounts, db.transactions},
      )
      .watch()
      .map((rows) {
        final result = <MonthlyRepayment>[];
        for (final row in rows) {
          final schedule = RepaymentSchedule.decode(
            row.readNullable<String>('repayment_schedule'),
          );
          final plan = schedule.plans[key];
          if (plan == null) continue;
          result.add(
            MonthlyRepayment(
              accountId: row.read<int>('id'),
              accountName: row.read<String>('name'),
              currency: row.read<String>('currency'),
              month: month,
              plan: plan,
              transferred: row.read<double>('transferred'),
            ),
          );
        }
        return result;
      });
}

Future<void> editRepaymentSchedule(
  BaseRepository repo,
  int accountId,
  RepaymentSchedule Function(RepaymentSchedule) update,
) async {
  Future<void> save() async {
    final account = await repo.getAccount(accountId);
    if (account == null) throw StateError('账户已被删除');
    final schedule = update(
      RepaymentSchedule.decode(account.repaymentSchedule),
    );
    await repo.updateAccount(accountId, repaymentSchedule: schedule.encode());
  }

  if (repo is LocalRepository) {
    await repo.db.transaction(save);
  } else {
    await save();
  }
}
