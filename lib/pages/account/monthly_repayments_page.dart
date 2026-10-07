import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../data/db.dart';
import '../../providers.dart';
import '../../providers/repayment_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/billing/repayment_schedule.dart';
import '../../styles/tokens.dart';
import '../../utils/beijing_time.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'repayment_plan_sheet.dart';

class MonthlyRepaymentsPage extends ConsumerStatefulWidget {
  final DateTime? initialMonth;
  final int? accountId;
  const MonthlyRepaymentsPage({super.key, this.initialMonth, this.accountId});

  @override
  ConsumerState<MonthlyRepaymentsPage> createState() =>
      _MonthlyRepaymentsPageState();
}

class _MonthlyRepaymentsPageState extends ConsumerState<MonthlyRepaymentsPage> {
  late DateTime _month;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final month = widget.initialMonth ?? beijingNow();
    _month = DateTime(month.year, month.month);
  }

  Future<void> _edit([Account? account]) async {
    if (account == null) {
      final accounts = ref.read(allAccountsStreamProvider).valueOrNull ?? [];
      final stats = ref.read(allAccountStatsProvider).valueOrNull ?? {};
      final eligible = accounts
          .where(
            (a) =>
                (widget.accountId == null || a.id == widget.accountId) &&
                canPlanRepayments(a, balance: stats[a.id]?.balance),
          )
          .toList();
      if (eligible.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              repaymentLabel(
                context,
                '请先添加信用卡、贷款或有透支余额的账户',
                'Add a credit card, loan or overdrawn account first',
              ),
            ),
          ),
        );
        return;
      }
      if (eligible.length == 1) {
        account = eligible.first;
      } else {
        account = await showModalBottomSheet<Account>(
          context: context,
          useSafeArea: true,
          builder: (context) => ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  repaymentLabel(context, '选择还款账户', 'Select an account'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final a in eligible)
                ListTile(
                  title: Text(a.name),
                  subtitle: Text(a.currency),
                  onTap: () => Navigator.pop(context, a),
                ),
            ],
          ),
        );
      }
    }
    if (!mounted || account == null) return;
    await showRepaymentPlanSheet(context, account, _month);
  }

  Future<void> _change(MonthlyRepayment item, {bool remove = false}) async {
    if (_saving) return;
    if (remove) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            repaymentLabel(context, '删除该月计划？', 'Remove this month’s plan?'),
          ),
          content: Text('${item.accountName} · ${repaymentMonthKey(_month)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(repaymentLabel(context, '取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(repaymentLabel(context, '删除', 'Remove')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await updateRepaymentSchedule(
        ref,
        item.accountId,
        (schedule) => remove
            ? schedule.remove(_month)
            : schedule.markPaid(_month, !item.plan.markedPaid),
      );
      if (!mounted) return;
      await PostProcessor.sync(
        ref,
        ledgerId: ref.read(currentLedgerIdProvider),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(allAccountsStreamProvider).valueOrNull ?? [];
    ref.watch(allAccountStatsProvider);
    final data = ref.watch(
      monthlyRepaymentsProvider(repaymentMonthKey(_month)),
    );
    final selectedAccount = accounts
        .where((a) => a.id == widget.accountId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: repaymentLabel(context, '月度还款', 'Monthly repayments'),
            subtitle: selectedAccount?.name,
            showBack: true,
            compact: true,
            actions: [
              IconButton(
                tooltip: repaymentLabel(context, '设置计划', 'Set plan'),
                onPressed: _saving ? null : () => _edit(selectedAccount),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _saving
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          final month = await showWheelDatePicker(
                            context,
                            initial: _month,
                            mode: WheelDatePickerMode.ym,
                            minDate: DateTime(2000),
                            maxDate: DateTime(2199, 12),
                          );
                          if (month != null && mounted) {
                            setState(
                              () => _month = DateTime(month.year, month.month),
                            );
                          }
                        },
                  child: Text(
                    repaymentMonthKey(_month),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Expanded(
            child: data.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (allItems) {
                final items = allItems
                    .where(
                      (item) =>
                          widget.accountId == null ||
                          item.accountId == widget.accountId,
                    )
                    .toList();
                final totals = <String, double>{};
                for (final item in items) {
                  totals.update(
                    item.currency,
                    (v) => v + item.remaining,
                    ifAbsent: () => item.remaining,
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    SectionCard(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            repaymentLabel(context, '待还款合计', 'Remaining due'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (totals.isEmpty)
                            const AmountText(value: 0, signed: false),
                          for (final entry in totals.entries)
                            AmountText(
                              value: entry.value,
                              signed: false,
                              showCurrency: true,
                              currencyCode: entry.key,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          const SizedBox(height: 8),
                          Text(
                            repaymentLabel(
                              context,
                              '当月转入还款自动抵扣；未记账的还款可标记已还。',
                              'Incoming repayments reduce this month’s due. Mark paid for repayments made outside the ledger.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          repaymentLabel(
                            context,
                            '该月还没有还款计划',
                            'No repayment plans for this month',
                          ),
                        ),
                      ),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          margin: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.accountName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    enabled: !_saving,
                                    onSelected: (value) async {
                                      if (value == 'remove') {
                                        await _change(item, remove: true);
                                      } else {
                                        final account = accounts
                                            .where(
                                              (a) => a.id == item.accountId,
                                            )
                                            .firstOrNull;
                                        if (account != null) {
                                          await _edit(account);
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text(
                                          repaymentLabel(
                                            context,
                                            '修改金额 / 分配月份',
                                            'Edit amount / months',
                                          ),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text(
                                          repaymentLabel(
                                            context,
                                            '删除本月计划',
                                            'Remove this month',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _RepaymentAmount(
                                    label: repaymentLabel(
                                      context,
                                      '计划',
                                      'Planned',
                                    ),
                                    value: item.plan.amount,
                                    currency: item.currency,
                                  ),
                                  _RepaymentAmount(
                                    label: repaymentLabel(
                                      context,
                                      '已还',
                                      'Paid',
                                    ),
                                    value: item.paid,
                                    currency: item.currency,
                                  ),
                                  _RepaymentAmount(
                                    label: repaymentLabel(
                                      context,
                                      '待还',
                                      'Remaining',
                                    ),
                                    value: item.remaining,
                                    currency: item.currency,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (item.remaining < .005)
                                Text(
                                  repaymentLabel(
                                    context,
                                    '本月已还清',
                                    'Settled for this month',
                                  ),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              TextButton.icon(
                                onPressed:
                                    _saving ||
                                        (!item.plan.markedPaid &&
                                            item.remaining < .005)
                                    ? null
                                    : () => _change(item),
                                icon: Icon(
                                  item.plan.markedPaid
                                      ? Icons.undo
                                      : Icons.check_circle_outline,
                                  size: 18,
                                ),
                                label: Text(
                                  repaymentLabel(
                                    context,
                                    item.plan.markedPaid ? '取消已还标记' : '标记已还',
                                    item.plan.markedPaid
                                        ? 'Clear paid mark'
                                        : 'Mark paid',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _edit(selectedAccount),
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        repaymentLabel(
                          context,
                          '设置金额并分配月份',
                          'Set amount and months',
                        ),
                      ),
                    ),
                    if (selectedAccount != null)
                      ..._plannedMonthLinks(selectedAccount),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _plannedMonthLinks(Account account) {
    try {
      final keys = RepaymentSchedule.decode(
        account.repaymentSchedule,
      ).plans.keys.toList()..sort();
      if (keys.isEmpty) return [];
      return [
        const SizedBox(height: 16),
        Text(repaymentLabel(context, '已设置的月份', 'Planned months')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final key in keys)
              ActionChip(
                label: Text(key),
                onPressed: _saving
                    ? null
                    : () => setState(() => _month = repaymentMonthFromKey(key)),
              ),
          ],
        ),
      ];
    } catch (e) {
      return [Text(e.toString())];
    }
  }
}

class _RepaymentAmount extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  const _RepaymentAmount({
    required this.label,
    required this.value,
    required this.currency,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AmountText(
            value: value,
            signed: false,
            showCurrency: true,
            currencyCode: currency,
          ),
        ),
      ],
    ),
  );
}
