import 'dart:convert';
import 'dart:math' as math;

String repaymentMonthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

DateTime repaymentMonthFromKey(String key) {
  if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(key)) {
    throw const FormatException('还款月份无效');
  }
  return DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5)));
}

List<DateTime> repaymentMonthRange(DateTime start, DateTime end) {
  final length = (end.year - start.year) * 12 + end.month - start.month + 1;
  if (length <= 0 || length > 1200) {
    throw const FormatException('结束月份不能早于开始月份，范围最多为100年');
  }
  return List.generate(length, (i) => DateTime(start.year, start.month + i));
}

class RepaymentPlan {
  final int amountMinor;
  final bool markedPaid;

  const RepaymentPlan({required this.amountMinor, this.markedPaid = false});

  double get amount => amountMinor / 100;

  RepaymentPlan copyWith({int? amountMinor, bool? markedPaid}) => RepaymentPlan(
    amountMinor: amountMinor ?? this.amountMinor,
    markedPaid: markedPaid ?? this.markedPaid,
  );

  Map<String, dynamic> toJson() => {
    'amountMinor': amountMinor,
    if (markedPaid) 'markedPaid': true,
  };
}

/// A month stores the total due for that account, rather than an extra instalment.
/// Paid flags acknowledge repayments made outside the ledger without creating money movements.
class RepaymentSchedule {
  final Map<String, RepaymentPlan> plans;

  RepaymentSchedule([Map<String, RepaymentPlan> plans = const {}])
    : plans = Map.unmodifiable(plans);

  factory RepaymentSchedule.decode(String? raw) {
    if (raw == null || raw.isEmpty) return RepaymentSchedule();
    final data = jsonDecode(raw);
    if (data is! Map || data['version'] != 1 || data['months'] is! Map) {
      throw const FormatException('还款计划格式无法读取');
    }
    final plans = <String, RepaymentPlan>{};
    for (final entry in (data['months'] as Map).entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map) {
        throw const FormatException('还款计划格式无法读取');
      }
      repaymentMonthFromKey(key);
      final amount = value['amountMinor'];
      if (amount is! int || amount <= 0) {
        throw const FormatException('还款金额无效');
      }
      plans[key] = RepaymentPlan(
        amountMinor: amount,
        markedPaid: value['markedPaid'] == true,
      );
    }
    return RepaymentSchedule(plans);
  }

  String encode() => jsonEncode({
    'version': 1,
    'months': {
      for (final key in (plans.keys.toList()..sort()))
        key: plans[key]!.toJson(),
    },
  });

  RepaymentSchedule assign(Iterable<DateTime> months, double amount) {
    if (!amount.isFinite || amount <= 0 || (amount * 100).round() <= 0) {
      throw const FormatException('请输入大于0的还款金额');
    }
    final next = Map<String, RepaymentPlan>.from(plans);
    for (final month in months) {
      final key = repaymentMonthKey(month);
      next[key] = RepaymentPlan(
        amountMinor: (amount * 100).round(),
        markedPaid: plans[key]?.markedPaid ?? false,
      );
    }
    return RepaymentSchedule(next);
  }

  RepaymentSchedule markPaid(DateTime month, bool paid) {
    final key = repaymentMonthKey(month);
    final plan = plans[key];
    if (plan == null) throw const FormatException('请先设置该月还款金额');
    return RepaymentSchedule({...plans, key: plan.copyWith(markedPaid: paid)});
  }

  RepaymentSchedule remove(DateTime month) => RepaymentSchedule(
    Map<String, RepaymentPlan>.from(plans)..remove(repaymentMonthKey(month)),
  );
}

class MonthlyRepayment {
  final int accountId;
  final String accountName;
  final String currency;
  final DateTime month;
  final RepaymentPlan plan;
  final double transferred;

  const MonthlyRepayment({
    required this.accountId,
    required this.accountName,
    required this.currency,
    required this.month,
    required this.plan,
    required this.transferred,
  });

  double get paid => plan.markedPaid
      ? plan.amount
      : math.min(plan.amount, math.max(0, transferred));
  double get remaining => math.max(0, plan.amount - paid);
}
