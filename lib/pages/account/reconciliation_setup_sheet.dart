import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../utils/beijing_time.dart';
import '../../utils/account_type_utils.dart';
import 'reconciliation_ui.dart';

Future<Set<int>?> selectReconciliationAccounts(
  BuildContext context,
  List<Account> accounts,
  Set<int> initial,
) {
  final selected = {...initial};
  var search = '';
  return showReconciliationSheet<Set<int>>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) {
        final visible = accounts
            .where((a) => a.name.toLowerCase().contains(search.toLowerCase()))
            .toList();
        return ReconciliationSheet(
          title: '选择对账账户',
          subtitle: '可同时核对资金账户、信用卡和花呗',
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索账户',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => change(() => search = value.trim()),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(accounts.isEmpty ? '暂无可对账账户' : '没有找到该账户'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final a = visible[i];
                          return ReconciliationCard(
                            selected: selected.contains(a.id),
                            padding: EdgeInsets.zero,
                            child: CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(a.name),
                              subtitle: Text(
                                '${getAccountTypeLabel(context, a.type)} · ${a.currency}',
                              ),
                              value: selected.contains(a.id),
                              onChanged: (v) => change(() {
                                if (v == true) {
                                  selected.add(a.id);
                                } else {
                                  selected.remove(a.id);
                                }
                              }),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          footer: Row(
            children: [
              Expanded(child: Text('已选 ${selected.length} 个账户')),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected),
                child: const Text('确认账户'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<DateTimeRange?> selectReconciliationPeriod(
  BuildContext context,
  DateTime start,
  DateTime end,
) {
  DateTime day(DateTime value) {
    final b = beijingTime(value);
    return DateTime(b.year, b.month, b.day);
  }

  final now = beijingNow();
  final today = DateTime(now.year, now.month, now.day);
  var from = day(start);
  var until = day(end);
  var editingStart = true;
  var preset = '自定义';
  return showReconciliationSheet<DateTimeRange>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) {
        final endsToday = until == today;
        return ReconciliationSheet(
          title: '对账期间',
          subtitle: '选择截图覆盖的开始和结束日期',
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in ['近7天', '近30天', '本月', '上月'])
                      ChoiceChip(
                        label: Text(label),
                        selected: preset == label,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        onSelected: (_) => change(() {
                          preset = label;
                          until = today;
                          from = switch (label) {
                            '近7天' => today.subtract(const Duration(days: 6)),
                            '近30天' => today.subtract(const Duration(days: 29)),
                            '本月' => DateTime(today.year, today.month),
                            _ => DateTime(today.year, today.month - 1),
                          };
                          if (label == '上月') {
                            until = DateTime(today.year, today.month, 0);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _PeriodEndpoint(
                  label: '开始日期',
                  value: from,
                  selected: editingStart,
                  onTap: () => change(() => editingStart = true),
                ),
                const SizedBox(height: 10),
                _PeriodEndpoint(
                  label: '结束日期',
                  value: until,
                  selected: !editingStart,
                  onTap: () => change(() => editingStart = false),
                ),
                const SizedBox(height: 12),
                Text(
                  editingStart ? '请选择开始日期' : '请选择结束日期',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                CalendarDatePicker(
                  key: ValueKey('$editingStart:$from:$until'),
                  initialDate: editingStart ? from : until,
                  firstDate: DateTime(2000),
                  lastDate: today,
                  onDateChanged: (date) => change(() {
                    preset = '自定义';
                    if (editingStart) {
                      from = date;
                      if (until.isBefore(from)) until = from;
                      editingStart = false;
                    } else {
                      until = date;
                      if (from.isAfter(until)) from = until;
                    }
                  }),
                ),
                ReconciliationNotice(
                  endsToday
                      ? '从开始日期 00:00:00 核对到今天确认期间的时刻（北京时间）。'
                      : '包含开始和结束日期当天的全部流水（北京时间）。',
                ),
              ],
            ),
          ),
          footer: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                DateTimeRange(
                  start: beijingDate(from.year, from.month, from.day).toUtc(),
                  end: endsToday
                      ? DateTime.now().toUtc()
                      : beijingDate(
                          until.year,
                          until.month,
                          until.day,
                          23,
                          59,
                          59,
                        ).toUtc(),
                ),
              ),
              child: const Text('确认期间'),
            ),
          ),
        );
      },
    ),
  );
}

class _PeriodEndpoint extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodEndpoint({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary.withValues(alpha: .08) : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? colors.primary : colors.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
