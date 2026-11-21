import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/billing/reimbursement_service.dart';
import '../../styles/liquid_theme.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/transaction_glass.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/bee_sheet.dart';
import '../../widgets/ui/capsule_switcher.dart';
import '../../widgets/ui/liquid_glass.dart';
import '../../widgets/ui/toast.dart';

enum _ReimbursementFilter { pending, settled, all }

class ReimbursementPage extends ConsumerStatefulWidget {
  final int? highlightTransactionId;

  const ReimbursementPage({super.key, this.highlightTransactionId});

  @override
  ConsumerState<ReimbursementPage> createState() => _ReimbursementPageState();
}

class _ReimbursementPageState extends ConsumerState<ReimbursementPage> {
  _ReimbursementFilter _filter = _ReimbursementFilter.pending;

  Future<void> _openSettleSheet(ReimbursementItem item) async {
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return;
    final allAccounts = await repo.getAllAccounts();
    final txCurrency = (item.original.currencyCode ?? '').toUpperCase();
    final accounts = allAccounts
        .where(
          (a) =>
              a.ledgerId == item.original.ledgerId &&
              !a.hidden &&
              (txCurrency.isEmpty || a.currency.toUpperCase() == txCurrency),
        )
        .toList();
    if (!mounted) return;

    final settled = await showBeeBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LiquidTheme.isActive(context)
          ? Colors.transparent
          : BeeTokens.surfaceSheet(context),
      builder: (_) => _ReimburseConfirmSheet(item: item, accounts: accounts),
    );
    if (settled == true && mounted) {
      ref.read(statsRefreshProvider.notifier).state++;
      ref.invalidate(
        reimbursementSummaryProvider(item.original.ledgerId),
      );
      showToast(context, '报销到账已登记（不计入真实收入）');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final summaryAsync = ref.watch(reimbursementSummaryProvider(ledgerId));
    final hideAmounts = ref.watch(hideAmountsProvider);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final liquid = LiquidTheme.isActive(context);
    final primary = Theme.of(context).colorScheme.primary;

    return TransactionScaffold(
      appBar: AppBar(title: const Text('待报销款')),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载待报销数据失败：$err'),
          ),
        ),
        data: (summary) {
          final filtered = switch (_filter) {
            _ReimbursementFilter.pending =>
              summary.items.where((e) => !e.isSettled).toList(),
            _ReimbursementFilter.settled =>
              summary.items.where((e) => e.isSettled).toList(),
            _ReimbursementFilter.all => summary.items,
          };

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SummaryCard(
                summary: summary,
                currencyCode: baseCurrency,
                hideAmounts: hideAmounts,
              ),
              const SizedBox(height: 16),
              CapsuleSwitcher<_ReimbursementFilter>(
                selectedValue: _filter,
                options: [
                  CapsuleOption(
                    value: _ReimbursementFilter.pending,
                    label: '待报销 (${summary.pendingCount})',
                  ),
                  CapsuleOption(
                    value: _ReimbursementFilter.settled,
                    label: '已报销 (${summary.settledCount})',
                  ),
                  CapsuleOption(
                    value: _ReimbursementFilter.all,
                    label: '全部 (${summary.items.length})',
                  ),
                ],
                onChanged: (v) {
                  if (liquid) GlassFeedback.selection(context);
                  setState(() => _filter = v);
                },
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 44,
                        color: BeeTokens.textTertiary(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _filter == _ReimbursementFilter.pending
                            ? '当前没有待报销款项'
                            : '暂无记录',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: BeeTokens.textSecondary(context),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '记支出时点选「待报销」即可在此独立跟踪，不计入真实收支',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: BeeTokens.textTertiary(context),
                            ),
                      ),
                    ],
                  ),
                )
              else
                for (final item in filtered)
                  _ReimbursementItemCard(
                    item: item,
                    highlighted:
                        widget.highlightTransactionId == item.original.id,
                    hideAmounts: hideAmounts,
                    primary: primary,
                    onSettle: item.isSettled
                        ? null
                        : () => _openSettleSheet(item),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ReimbursementSummary summary;
  final String currencyCode;
  final bool hideAmounts;

  const _SummaryCard({
    required this.summary,
    required this.currencyCode,
    required this.hideAmounts,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: primary),
              const SizedBox(width: 6),
              Text(
                '待报销总额（独立统计）',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: BeeTokens.textSecondary(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AmountText(
            value: summary.totalPendingNative,
            hide: hideAmounts,
            signed: false,
            showCurrency: true,
            currencyCode: currencyCode,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '待报销 ${summary.pendingCount} 笔',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: BeeTokens.textSecondary(context),
                      ),
                ),
              ),
              Text(
                hideAmounts
                    ? '已报销 ****'
                    : '累计已报销 ${summary.totalReimbursedNative.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: BeeTokens.textSecondary(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '待报销支出与报销到账均不计入真实收支和预算，仅真实影响账户余额。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BeeTokens.textTertiary(context),
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
    return TransactionPanel(prominent: true, child: content);
  }
}

class _ReimbursementItemCard extends StatelessWidget {
  final ReimbursementItem item;
  final bool highlighted;
  final bool hideAmounts;
  final Color primary;
  final VoidCallback? onSettle;

  const _ReimbursementItemCard({
    required this.item,
    required this.highlighted,
    required this.hideAmounts,
    required this.primary,
    this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final tx = item.original;
    final catName = item.category != null
        ? CategoryUtils.getDisplayName(item.category!.name, context)
        : '支出';
    final title = (tx.note != null && tx.note!.trim().isNotEmpty)
        ? tx.note!.trim()
        : catName;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(tx.happenedAt.toLocal());
    final statusColor = item.isSettled
        ? Colors.green.shade600
        : item.isPartial
            ? Colors.orange.shade700
            : primary;
    final statusText = item.isSettled
        ? '已报销'
        : item.isPartial
            ? '部分报销'
            : '待报销';

    return TransactionCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: highlighted
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primary.withValues(alpha: .6), width: 1.5),
              )
            : null,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (item.category != null)
                  CategoryIconWidget(
                    category: item.category!,
                    size: 36,
                    circular: true,
                  )
                else
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: primary.withValues(alpha: .12),
                    child: Icon(Icons.receipt_long_outlined,
                        size: 18, color: primary),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          catName,
                          if (item.account != null) item.account!.name,
                          dateStr,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: BeeTokens.textSecondary(context),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.isSettled
                            ? '原支出 ${hideAmounts ? "****" : tx.amount.toStringAsFixed(2)}'
                            : item.isPartial
                                ? '已报销 ${hideAmounts ? "****" : item.reimbursedAmount.toStringAsFixed(2)} · 待收 ${hideAmounts ? "****" : item.remainingAmount.toStringAsFixed(2)}'
                                : '待报销金额',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: BeeTokens.textSecondary(context),
                            ),
                      ),
                      const SizedBox(height: 2),
                      AmountText(
                        value: item.isSettled ? tx.amount : item.remainingAmount,
                        hide: hideAmounts,
                        signed: false,
                        showCurrency: true,
                        currencyCode: tx.currencyCode,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: item.isSettled
                                  ? BeeTokens.textSecondary(context)
                                  : BeeTokens.textPrimary(context),
                            ),
                      ),
                    ],
                  ),
                ),
                if (onSettle != null)
                  FilledButton.tonalIcon(
                    onPressed: onSettle,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('确认报销'),
                  ),
              ],
            ),
            if (item.reimbursements.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: BeeTokens.border(context)),
              const SizedBox(height: 8),
              for (final payout in item.reimbursements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right,
                          size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${DateFormat('yyyy-MM-dd').format(payout.happenedAt.toLocal())} 到账${payout.note != null && payout.note!.isNotEmpty ? ' · ${payout.note}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: BeeTokens.textSecondary(context),
                                  ),
                        ),
                      ),
                      Text(
                        hideAmounts
                            ? '****'
                            : '+${payout.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReimburseConfirmSheet extends ConsumerStatefulWidget {
  final ReimbursementItem item;
  final List<Account> accounts;

  const _ReimburseConfirmSheet({
    required this.item,
    required this.accounts,
  });

  @override
  ConsumerState<_ReimburseConfirmSheet> createState() =>
      _ReimburseConfirmSheetState();
}

class _ReimburseConfirmSheetState
    extends ConsumerState<_ReimburseConfirmSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  int? _accountId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.item.remainingAmount.toStringAsFixed(2),
    );
    _noteCtrl = TextEditingController(text: '报销到账');
    final preferred = widget.item.original.accountId;
    if (preferred != null && widget.accounts.any((a) => a.id == preferred)) {
      _accountId = preferred;
    } else if (widget.accounts.isNotEmpty) {
      _accountId = widget.accounts.first.id;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final val = double.tryParse(_amountCtrl.text.trim());
    if (val == null || !val.isFinite || val <= 0) {
      setState(() => _error = '请输入有效的报销到账金额');
      return;
    }
    if (val > widget.item.remainingAmount + 0.005) {
      setState(
        () => _error =
            '不能超过剩余待报销金额（${widget.item.remainingAmount.toStringAsFixed(2)}）',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (repo is! LocalRepository) throw StateError('Local repo unavailable');
      await ReimbursementService(repo).reimburse(
        originalId: widget.item.original.id,
        amount: val,
        happenedAt: _date,
        accountId: _accountId,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      await PostProcessor.run(ref, ledgerId: widget.item.original.ledgerId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '登记报销到账',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '剩余待报销 ${widget.item.remainingAmount.toStringAsFixed(2)} · 到账后增加收款账户余额，不计入真实收入',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: BeeTokens.textSecondary(context),
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '报销到账金额',
                  border: transactionInputBorder(context),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.accounts.isNotEmpty)
                DropdownButtonFormField<int?>(
                  value: _accountId,
                  decoration: InputDecoration(
                    labelText: '收款账户',
                    border: transactionInputBorder(context),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('不指定账户'),
                    ),
                    for (final acc in widget.accounts)
                      DropdownMenuItem<int?>(
                        value: acc.id,
                        child: Text('${acc.name} (${acc.currency})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '到账日期',
                    border: transactionInputBorder(context),
                    suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: '备注',
                  border: transactionInputBorder(context),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? '保存中...' : '确认到账'),
              ),
            ],
          ),
        ),
      ),
    );
    return LiquidTheme.isActive(context)
        ? TransactionGlass(prominent: true, borderRadius: 28, child: content)
        : content;
  }
}
