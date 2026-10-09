import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/reconciliation/reconciliation_models.dart';
import '../../services/reconciliation/reconciliation_store.dart';
import '../../utils/beijing_time.dart';

Future<Json?> editReconciliationMutation(
  BuildContext context,
  Json mutation,
  ReconciliationSession session,
  ReconciliationSnapshot snapshot,
) async {
  if (mutation['after'] == null) return null;
  final draft = jsonObject(mutation['after']);
  var type = draft['type'] as String;
  int? accountId = draft['accountId'];
  int? toAccountId = draft['toAccountId'];
  int? categoryId = draft['categoryId'];
  int ledgerId = draft['ledgerId'];
  if (!snapshot.ledgers.any((l) => l.id == ledgerId && !l.isShared)) {
    ledgerId = session.defaultLedgerId;
  }
  String? refund = draft['refundOfSyncId'];
  final amount = TextEditingController(text: moneyText(draft['amountCents']));
  final time = TextEditingController(
    text: DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(beijingTime(evidenceTime(draft['happenedAt'])!)),
  );
  final note = TextEditingController(text: draft['note'] ?? '');
  final merchant = TextEditingController(text: draft['merchant'] ?? '');
  final item = TextEditingController(text: draft['itemDescription'] ?? '');
  final channel = TextEditingController(text: draft['paymentChannel'] ?? '');
  final form = GlobalKey<FormState>();
  final accounts = snapshot.accounts
      .where((a) => session.accounts.any((s) => s.id == a.id))
      .toList();
  final originals = snapshot.records
      .where((t) => t.type == 'expense' && t.amount > 0 && t.syncId != null)
      .toList();
  if (!accounts.any((a) => a.id == accountId)) accountId = null;
  if (!accounts.any((a) => a.id == toAccountId)) toAccountId = null;
  final result = await showDialog<Json>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('编辑修改建议'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: const [
                      DropdownMenuItem(value: 'expense', child: Text('支出／退款')),
                      DropdownMenuItem(value: 'income', child: Text('收入')),
                      DropdownMenuItem(value: 'transfer', child: Text('转账')),
                    ],
                    onChanged: (v) => setState(() {
                      type = v!;
                      categoryId = null;
                    }),
                  ),
                  TextFormField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: '金额（退款填负数）'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (v) {
                      try {
                        return moneyCents(v) == null ? '请填写金额' : null;
                      } catch (e) {
                        return '$e';
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    value: accountId,
                    decoration: const InputDecoration(labelText: '资金账户／转出账户'),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => accountId = v),
                    validator: (v) => v == null ? '请选择账户' : null,
                  ),
                  if (type == 'transfer')
                    DropdownButtonFormField<int>(
                      value: toAccountId,
                      decoration: const InputDecoration(labelText: '转入账户'),
                      items: accounts
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => toAccountId = v),
                      validator: (v) => v == null ? '请选择账户' : null,
                    ),
                  if (mutation['transactionId'] == null)
                    DropdownButtonFormField<int>(
                      value: ledgerId,
                      decoration: const InputDecoration(labelText: '入账账本'),
                      items: snapshot.ledgers
                          .where((l) => !l.isShared)
                          .map(
                            (l) => DropdownMenuItem(
                              value: l.id,
                              child: Text(l.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => ledgerId = v!),
                    ),
                  if (type != 'transfer')
                    DropdownButtonFormField<int>(
                      value:
                          snapshot.categories.any(
                            (c) => c.id == categoryId && c.kind == type,
                          )
                          ? categoryId
                          : null,
                      decoration: const InputDecoration(labelText: '分类'),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('未分类'),
                        ),
                        ...snapshot.categories
                            .where((c) => c.kind == type)
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            ),
                      ],
                      onChanged: (v) => setState(() => categoryId = v),
                    ),
                  TextFormField(
                    controller: time,
                    decoration: const InputDecoration(
                      labelText: '北京时间（年-月-日 时:分:秒）',
                    ),
                    validator: (v) =>
                        evidenceTime(v) == null ? '请填写有效时间' : null,
                  ),
                  if (type == 'expense' && draft['refundOfMutationId'] == null)
                    DropdownButtonFormField<String>(
                      value: originals.any((t) => t.syncId == refund)
                          ? refund
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '退款关联原支出'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('不关联'),
                        ),
                        ...originals.map(
                          (t) => DropdownMenuItem(
                            value: t.syncId,
                            child: Text(
                              '#${t.id} ${t.merchant ?? t.note ?? ''} ${t.amount.toStringAsFixed(2)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => refund = v),
                    ),
                  TextFormField(
                    controller: merchant,
                    decoration: const InputDecoration(labelText: '商家'),
                  ),
                  TextFormField(
                    controller: item,
                    decoration: const InputDecoration(labelText: '商品描述'),
                  ),
                  TextFormField(
                    controller: channel,
                    decoration: const InputDecoration(labelText: '支付渠道'),
                  ),
                  TextFormField(
                    controller: note,
                    decoration: const InputDecoration(labelText: '备注'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                ...draft,
                'type': type,
                'amountCents': moneyCents(amount.text),
                'accountId': accountId,
                'toAccountId': type == 'transfer' ? toAccountId : null,
                'categoryId': type == 'transfer' ? null : categoryId,
                'ledgerId': ledgerId,
                'happenedAt': evidenceTime(time.text)!.toIso8601String(),
                'note': note.text,
                'merchant': merchant.text,
                'itemDescription': item.text,
                'paymentChannel': channel.text,
                'refundOfSyncId': type == 'expense' ? refund : null,
              });
            },
            child: const Text('保存建议'),
          ),
        ],
      ),
    ),
  );
  for (final controller in [amount, time, note, merchant, item, channel]) {
    controller.dispose();
  }
  return result;
}
