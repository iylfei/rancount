import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../providers.dart';
import '../../providers/repayment_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/billing/repayment_schedule.dart';
import '../../widgets/ui/wheel_date_picker.dart';

String repaymentLabel(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

Future<void> showRepaymentPlanSheet(
  BuildContext context,
  Account account,
  DateTime month,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => RepaymentPlanSheet(account: account, month: month),
);

class RepaymentPlanSheet extends ConsumerStatefulWidget {
  final Account account;
  final DateTime month;
  const RepaymentPlanSheet({
    super.key,
    required this.account,
    required this.month,
  });

  @override
  ConsumerState<RepaymentPlanSheet> createState() => _RepaymentPlanSheetState();
}

class _RepaymentPlanSheetState extends ConsumerState<RepaymentPlanSheet> {
  late final TextEditingController _amount;
  late final Set<String> _selected;
  late int _year;
  late DateTime _start;
  late DateTime _end;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _year = widget.month.year;
    _start = _end = DateTime(widget.month.year, widget.month.month);
    _selected = {repaymentMonthKey(widget.month)};
    try {
      final current = RepaymentSchedule.decode(
        widget.account.repaymentSchedule,
      ).plans[repaymentMonthKey(widget.month)];
      _amount = TextEditingController(
        text: current?.amount.toStringAsFixed(2) ?? '',
      );
    } catch (e) {
      _amount = TextEditingController();
      _error = e.toString();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickRangeMonth(bool start) async {
    final value = await showWheelDatePicker(
      context,
      initial: start ? _start : _end,
      mode: WheelDatePickerMode.ym,
      minDate: DateTime(2000),
      maxDate: DateTime(2199, 12),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        (amount * 100).round() == 0) {
      setState(
        () => _error = repaymentLabel(
          context,
          '请输入大于0的金额',
          'Enter a positive amount',
        ),
      );
      return;
    }
    if (_selected.isEmpty) {
      setState(
        () => _error = repaymentLabel(
          context,
          '请至少选择一个月份',
          'Select at least one month',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await updateRepaymentSchedule(
        ref,
        widget.account.id,
        (schedule) =>
            schedule.assign(_selected.map(repaymentMonthFromKey), amount),
      );
      if (!mounted) return;
      await PostProcessor.sync(
        ref,
        ledgerId: ref.read(currentLedgerIdProvider),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected.toList()..sort();
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                repaymentLabel(context, '设置还款计划', 'Repayment plan'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('${widget.account.name} · ${widget.account.currency}'),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: repaymentLabel(
                    context,
                    '每个选中月份的待还金额',
                    'Amount due in each selected month',
                  ),
                  suffixText: widget.account.currency,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => _pickRangeMonth(true),
                      child: Text(
                        '${repaymentLabel(context, '开始', 'From')} ${repaymentMonthKey(_start)}',
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => _pickRangeMonth(false),
                      child: Text(
                        '${repaymentLabel(context, '结束', 'To')} ${repaymentMonthKey(_end)}',
                      ),
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        try {
                          final range = repaymentMonthRange(_start, _end);
                          setState(() {
                            _selected.addAll(range.map(repaymentMonthKey));
                            _error = null;
                          });
                        } catch (e) {
                          setState(() => _error = e.toString());
                        }
                      },
                child: Text(
                  repaymentLabel(
                    context,
                    '选择这段连续月份',
                    'Select this month range',
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _saving || _year <= 2000
                        ? null
                        : () => setState(() => _year--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$_year',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving || _year >= 2199
                        ? null
                        : () => setState(() => _year++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  for (var m = 1; m <= 12; m++)
                    FilterChip(
                      label: Text(repaymentLabel(context, '$m月', '$m')),
                      selected: _selected.contains(
                        repaymentMonthKey(DateTime(_year, m)),
                      ),
                      showCheckmark: true,
                      onSelected: _saving
                          ? null
                          : (on) => setState(() {
                              final key = repaymentMonthKey(DateTime(_year, m));
                              if (on) {
                                _selected.add(key);
                              } else {
                                _selected.remove(key);
                              }
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                repaymentLabel(
                  context,
                  '已选 ${selected.length} 个月',
                  '${selected.length} months selected',
                ),
              ),
              if (selected.isNotEmpty) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 84),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final key in selected)
                          InputChip(
                            label: Text(key),
                            onDeleted: _saving
                                ? null
                                : () => setState(() => _selected.remove(key)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                repaymentLabel(
                  context,
                  '金额会分别应用到每个月，替换该月原计划；已还标记保留。',
                  'This amount replaces each selected month’s plan. Paid marks are kept.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  repaymentLabel(
                    context,
                    _saving ? '保存中…' : '保存计划',
                    _saving ? 'Saving…' : 'Save plan',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
