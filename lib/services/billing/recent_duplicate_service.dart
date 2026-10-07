import 'package:drift/drift.dart';

import '../../data/repositories/local/local_repository.dart';

/// 新记录按实际入账时间判断；升级前没有入账时间的记录按交易时间兜底。
class RecentDuplicateService {
  static const window = Duration(hours: 24);

  static Future<bool> exists({
    required LocalRepository repository,
    required double amount,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await repository.db
        .customSelect(
          'SELECT 1 FROM transactions t '
          'LEFT JOIN recent_transaction_records r ON r.transaction_id = t.id '
          'WHERE ABS(t.amount - ?) < 0.005 '
          'AND ((r.recorded_at >= ? AND r.recorded_at <= ?) '
          'OR (r.transaction_id IS NULL '
          'AND t.happened_at >= ? AND t.happened_at <= ?)) LIMIT 1',
          variables: [
            Variable<double>(amount.abs()),
            Variable<int>(now - window.inSeconds),
            Variable<int>(now),
            Variable<int>(now - window.inSeconds),
            Variable<int>(now),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }
}
