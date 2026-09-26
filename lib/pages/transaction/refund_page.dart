import '../../widgets/biz/transaction_glass.dart';
import '../../styles/liquid_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/billing/refund_service.dart';

class RefundPage extends ConsumerStatefulWidget {
  final Transaction original;
  final Transaction? existing;

  const RefundPage({super.key, required this.original, this.existing});

  @override
  ConsumerState<RefundPage> createState() => _RefundPageState();
}

class _RefundPageState extends ConsumerState<RefundPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController(text: '退款');
  double? _remaining;
  List<Account> _accounts = [];
  int? _accountId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amount.text = existing.amount.abs().toStringAsFixed(2);
      _note.text = existing.note ?? '';
      _date = existing.happenedAt;
    }
    _load().catchError((Object _) {
      if (mounted) setState(() => _error = '无法读取原支出，请返回后重试');
    });
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return;
    final remaining = await RefundService(repo).remaining(widget.original.id);
    final accounts = await repo.getAllAccounts();
    if (!mounted) return;
    setState(() {
      _remaining = remaining + (widget.existing?.amount.abs() ?? 0);
      _accounts = accounts
          .where(
            (a) =>
                a.ledgerId == widget.original.ledgerId &&
                !a.hidden &&
                a.currency.toUpperCase() ==
                    (widget.original.currencyCode ?? a.currency).toUpperCase(),
          )
          .toList();
      final preferred = widget.existing == null
          ? widget.original.accountId
          : widget.existing!.accountId;
      _accountId = _accounts.any((a) => a.id == preferred) ? preferred : null;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(
        () => _date = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = double.tryParse(_amount.text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      setState(() => _error = '请输入有效退款金额');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (repo is! LocalRepository) {
        throw StateError('Local ledger unavailable');
      }
      final service = RefundService(repo);
      final existing = widget.existing;
      if (existing == null) {
        await service.create(
          originalId: widget.original.id,
          amount: value,
          happenedAt: _date,
          accountId: _accountId,
          note: _note.text.trim(),
        );
      } else {
        await service.update(
          refundId: existing.id,
          amount: value,
          happenedAt: _date,
          accountId: _accountId,
          note: _note.text.trim(),
        );
      }
      if (!mounted) return;
      await PostProcessor.run(ref, ledgerId: widget.original.ledgerId);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '退款金额超出剩余可退金额，或保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => TransactionScaffold(
        appBar: AppBar(title: Text(widget.existing == null ? '关联退款' : '编辑退款')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (LiquidTheme.isActive(context))
              TransactionPanel(
                prominent: true,
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '原支出：${widget.original.amount.toStringAsFixed(2)} '
                      '${widget.original.currencyCode ?? 'CNY'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Text('剩余可退', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      _remaining?.toStringAsFixed(2) ?? '…',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                '原支出：${widget.original.amount.toStringAsFixed(2)} '
                '${widget.original.currencyCode ?? 'CNY'}',
              ),
              const SizedBox(height: 8),
              Text('剩余可退：${_remaining?.toStringAsFixed(2) ?? '…'}'),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '本次退款金额'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _accountId,
              decoration: const InputDecoration(labelText: '退款到账账户'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('不关联账户')),
                for (final account in _accounts)
                  DropdownMenuItem<int?>(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('退款日期'),
              subtitle: Text('${_date.year}-${_date.month}-${_date.day}'),
              trailing: const Icon(Icons.event),
              onTap: _pickDate,
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving || _remaining == null || _remaining! <= 0
                  ? null
                  : _save,
              child: Text(widget.existing == null ? '确认退款' : '保存退款'),
            ),
          ],
        ),
      );
}
