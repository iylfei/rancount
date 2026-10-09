import 'package:flutter/material.dart';

import '../../data/db.dart' as db;
import '../../services/reconciliation/reconciliation_models.dart';
import '../../services/reconciliation/reconciliation_store.dart';
import 'reconciliation_ui.dart';

Future<Json?> editReconciliationMutation(
  BuildContext context,
  Json mutation,
  ReconciliationSession session,
  ReconciliationSnapshot snapshot,
) {
  if (mutation['after'] == null) return Future.value();
  return showReconciliationSheet<Json>(
    context,
    builder: (_) => _MutationEditor(
      mutation: mutation,
      session: session,
      snapshot: snapshot,
    ),
  );
}

class _MutationEditor extends StatefulWidget {
  final Json mutation;
  final ReconciliationSession session;
  final ReconciliationSnapshot snapshot;
  const _MutationEditor({
    required this.mutation,
    required this.session,
    required this.snapshot,
  });
  @override
  State<_MutationEditor> createState() => _MutationEditorState();
}

class _MutationEditorState extends State<_MutationEditor> {
  final _form = GlobalKey<FormState>();
  late Json _draft;
  late String _type;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  late int _ledgerId;
  String? _refund;
  late DateTime _time;
  late TextEditingController _amount;
  late TextEditingController _merchant;
  late TextEditingController _item;
  late TextEditingController _channel;
  late TextEditingController _note;
  List<db.Account> get _accounts => widget.snapshot.accounts
      .where((a) => widget.session.accounts.any((s) => s.id == a.id))
      .toList();
  List<db.Transaction> get _originals =>
      widget.snapshot.records
          .where(
            (t) =>
                t.type == 'expense' &&
                t.amount > 0 &&
                t.syncId != null &&
                t.ledgerId == _ledgerId &&
                t.currencyCode ==
                    _accounts
                        .where((a) => a.id == _accountId)
                        .firstOrNull
                        ?.currency,
          )
          .toList()
        ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));

  @override
  void initState() {
    super.initState();
    _draft = jsonObject(widget.mutation['after']);
    _type = _draft['type'] == 'expense' && (_draft['amountCents'] as int) < 0
        ? 'refund'
        : _draft['type'];
    _accountId = _draft['accountId'];
    _toAccountId = _draft['toAccountId'];
    _categoryId = _draft['categoryId'];
    _ledgerId = _draft['ledgerId'];
    if (!widget.snapshot.ledgers.any((l) => l.id == _ledgerId && !l.isShared)) {
      _ledgerId = widget.session.defaultLedgerId;
    }
    if (!_accounts.any((a) => a.id == _accountId)) _accountId = null;
    if (!_accounts.any((a) => a.id == _toAccountId)) _toAccountId = null;
    _refund = _draft['refundOfSyncId'];
    _time = evidenceTime(_draft['happenedAt'])!;
    _amount = TextEditingController(
      text: moneyText((_draft['amountCents'] as int).abs()),
    );
    _merchant = TextEditingController(text: _draft['merchant'] ?? '');
    _item = TextEditingController(text: _draft['itemDescription'] ?? '');
    _channel = TextEditingController(text: _draft['paymentChannel'] ?? '');
    _note = TextEditingController(text: _draft['note'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [_amount, _merchant, _item, _channel, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      ..._draft,
      'type': _type == 'refund' ? 'expense' : _type,
      'amountCents': moneyCents(_amount.text)! * (_type == 'refund' ? -1 : 1),
      'accountId': _accountId,
      'toAccountId': _type == 'transfer' ? _toAccountId : null,
      'categoryId': _type == 'transfer' ? null : _categoryId,
      'ledgerId': _ledgerId,
      'happenedAt': _time.toIso8601String(),
      'merchant': _merchant.text,
      'itemDescription': _item.text,
      'paymentChannel': _channel.text,
      'note': _note.text,
      'refundOfSyncId': _type == 'refund' ? _refund : null,
      'refundOfMutationId': _type == 'refund'
          ? _draft['refundOfMutationId']
          : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = _type == 'refund' ? 'expense' : _type;
    final currency = _accounts
        .where((a) => a.id == _accountId)
        .firstOrNull
        ?.currency;
    final refundOriginal = _originals
        .where((t) => t.syncId == _refund)
        .firstOrNull;
    Widget gap(Widget child) =>
        Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
    return ReconciliationSheet(
      title: '编辑修改建议',
      subtitle: '保存后回到审核页，确认应用才会修改记账记录',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              gap(
                DropdownButtonFormField<String>(
                  value: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '记录类型'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('支出')),
                    DropdownMenuItem(value: 'income', child: Text('收入')),
                    DropdownMenuItem(value: 'transfer', child: Text('账户间转账')),
                    DropdownMenuItem(value: 'refund', child: Text('支出退款')),
                  ],
                  onChanged: (v) => setState(() {
                    final nextKind = v == 'refund' ? 'expense' : v;
                    if (kind != nextKind) _categoryId = null;
                    _type = v!;
                  }),
                ),
              ),
              gap(
                TextFormField(
                  controller: _amount,
                  decoration: InputDecoration(
                    labelText: '金额',
                    suffixText: currency,
                    helperText: '填写正数，收支方向由记录类型决定',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    try {
                      final cents = moneyCents(v);
                      return cents == null || cents <= 0 ? '请填写大于零的金额' : null;
                    } catch (e) {
                      return '$e';
                    }
                  },
                ),
              ),
              gap(
                DropdownButtonFormField<int>(
                  value: _accountId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _type == 'transfer'
                        ? '转出账户'
                        : _type == 'expense'
                        ? '付款账户'
                        : '收款账户',
                  ),
                  items: _accounts
                      .map(
                        (a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _accountId = v;
                    if (!_originals.any((t) => t.syncId == _refund)) {
                      _refund = null;
                    }
                  }),
                  validator: (v) => v == null ? '请选择账户' : null,
                ),
              ),
              if (_type == 'transfer')
                gap(
                  DropdownButtonFormField<int>(
                    value: _toAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '转入账户'),
                    items: _accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _toAccountId = v),
                    validator: (v) => v == null
                        ? '请选择转入账户'
                        : v == _accountId
                        ? '转入和转出账户需不同'
                        : null,
                  ),
                ),
              if (widget.mutation['transactionId'] == null)
                gap(
                  DropdownButtonFormField<int>(
                    value: _ledgerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '保存到账本'),
                    items: widget.snapshot.ledgers
                        .where((l) => !l.isShared)
                        .map(
                          (l) => DropdownMenuItem(
                            value: l.id,
                            child: Text(l.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _ledgerId = v!;
                      _refund = null;
                    }),
                  ),
                ),
              if (_type != 'transfer')
                gap(
                  DropdownButtonFormField<int>(
                    value:
                        widget.snapshot.categories.any(
                          (c) => c.id == _categoryId && c.kind == kind,
                        )
                        ? _categoryId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '分类'),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('未分类'),
                      ),
                      ...widget.snapshot.categories
                          .where((c) => c.kind == kind)
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          ),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
              gap(
                ReconciliationField(
                  label: '交易时间 · 北京时间',
                  value: reconciliationDate(_time, time: true),
                  icon: Icons.schedule,
                  onTap: () async {
                    final value = await pickReconciliationTime(
                      context,
                      title: '交易时间',
                      initial: _time,
                      first: widget.session.start,
                      last: widget.session.end,
                    );
                    if (value != null && mounted) setState(() => _time = value);
                  },
                ),
              ),
              if (_type == 'refund')
                gap(
                  ReconciliationField(
                    label: '关联原支出',
                    icon: Icons.receipt_long_outlined,
                    value: _draft['refundOfMutationId'] != null
                        ? '本组建议中新增的原支出'
                        : refundOriginal == null
                        ? '未关联原支出'
                        : '${refundOriginal.merchant ?? refundOriginal.note ?? '支出'} · ${refundOriginal.amount.toStringAsFixed(2)}',
                    onTap: _draft['refundOfMutationId'] != null
                        ? null
                        : () async {
                            final result = await _pickRefund(
                              context,
                              _originals,
                              _refund,
                            );
                            if (result != null && mounted) {
                              setState(() {
                                _refund = result.isEmpty ? null : result;
                                final original = _originals
                                    .where((t) => t.syncId == _refund)
                                    .firstOrNull;
                                if (original != null) {
                                  _categoryId = original.categoryId;
                                }
                              });
                            }
                          },
                  ),
                ),
              ExpansionTile(
                title: const Text('商家、描述和备注（选填）'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: [
                  _merchant,
                  _item,
                  _channel,
                  _note,
                ].any((c) => c.text.isNotEmpty),
                children: [
                  gap(
                    TextFormField(
                      controller: _merchant,
                      decoration: const InputDecoration(labelText: '商家'),
                    ),
                  ),
                  gap(
                    TextFormField(
                      controller: _item,
                      decoration: const InputDecoration(labelText: '商品或交易描述'),
                    ),
                  ),
                  gap(
                    TextFormField(
                      controller: _channel,
                      decoration: const InputDecoration(labelText: '支付渠道'),
                    ),
                  ),
                  gap(
                    TextFormField(
                      controller: _note,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '备注'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: _save, child: const Text('保存建议')),
      ),
    );
  }
}

Future<String?> _pickRefund(
  BuildContext context,
  List<db.Transaction> originals,
  String? selected,
) {
  var search = '';
  return showReconciliationSheet<String>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) {
        final visible = originals
            .where(
              (t) =>
                  '${t.merchant ?? ''} ${t.note ?? ''} ${t.amount.toStringAsFixed(2)}'
                      .contains(search),
            )
            .toList();
        return ReconciliationSheet(
          title: '选择退款对应的原支出',
          subtitle: '仅显示同账本、同币种的支出',
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索商家、备注或金额',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => change(() => search = v.trim()),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('没有符合条件的原支出'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final t = visible[i];
                          return ListTile(
                            title: Text(t.merchant ?? t.note ?? '支出'),
                            subtitle: Text(
                              reconciliationDate(t.happenedAt, time: true),
                            ),
                            trailing: Text(t.amount.toStringAsFixed(2)),
                            selected: selected == t.syncId,
                            onTap: () => Navigator.pop(context, t.syncId),
                          );
                        },
                      ),
              ),
            ],
          ),
          footer: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('暂不关联原支出'),
            ),
          ),
        );
      },
    ),
  );
}
