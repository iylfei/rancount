import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/utils/beijing_time.dart';
import 'package:beecount/utils/month_range.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('month boundaries and period labels use UTC+08 for UTC instants', () {
    final range = periodForLabel(2026, 9, 1);
    expect(range.start.toUtc(), DateTime.utc(2026, 8, 31, 16));
    expect(range.end.toUtc(), DateTime.utc(2026, 9, 30, 16));
    expect(labelForDate(DateTime.utc(2026, 8, 31, 16), 1).month, 9);
    expect(labelForDate(DateTime.utc(2026, 8, 31, 15, 59), 1).month, 8);
    expect(beijingTime(DateTime.utc(2026, 9, 1)).hour, 8);
  });
  test('daily and monthly totals agree at Beijing midnight', () async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    final repo = LocalRepository(db);
    try {
      final ledger = await repo.createLedger(name: '日常');
      for (final (time, amount) in [
        (DateTime.utc(2026, 8, 31, 15, 59, 59), 10.0),
        (DateTime.utc(2026, 8, 31, 16), 20.0),
        (DateTime.utc(2026, 9, 30, 16), 30.0),
      ]) {
        await repo.addTransaction(
            ledgerId: ledger,
            type: 'expense',
            amount: amount,
            happenedAt: time);
      }
      expect(
          (await repo.monthlyTotals(ledgerId: ledger, month: DateTime(2026, 9)))
              .$2,
          20);
      final days = await repo.getDailyTotalsByMonth(
          ledgerId: ledger, month: DateTime(2026, 9));
      expect(days.keys, ['2026-09-01']);
      expect(days['2026-09-01']!.$2, 20);
    } finally {
      await db.close();
    }
  });
}
