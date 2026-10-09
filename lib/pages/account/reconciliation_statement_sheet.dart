import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../services/reconciliation/reconciliation_models.dart';
import 'reconciliation_ui.dart';

Future<StatementRow?> editReconciliationStatement(
  BuildContext context,
  ReconciliationAccount account,
  DateTime defaultTime,
  StatementRow? existing,
) async {
  final amount = TextEditingController(
    text: existing?.delta == null ? '' : moneyText(existing!.delta!.abs()),
  );
  final balance = TextEditingController(
    text: existing?.balanceAfter == null
        ? ''
        : moneyText(existing!.balanceAfter!),
  );
  final description = TextEditingController(text: existing?.description ?? '');
  var incoming = (existing?.delta ?? -1) > 0;
  DateTime? time = existing == null ? defaultTime : existing.time;
  var timeError = false;
  final form = GlobalKey<FormState>();
  final result = await showReconciliationSheet<StatementRow>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) => ReconciliationSheet(
        title: existing == null ? '补充一条流水' : '编辑识别流水',
        subtitle: account.name,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ReconciliationNotice(
                  '填写账户实际发生的交易。这里保存的是对账资料，审核建议后才会修改记账记录。',
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('流出'),
                      icon: Icon(Icons.north_east),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('流入'),
                      icon: Icon(Icons.south_west),
                    ),
                  ],
                  selected: {incoming},
                  onSelectionChanged: (v) => change(() => incoming = v.single),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  decoration: InputDecoration(
                    labelText: '变动金额',
                    suffixText: account.currency,
                    helperText: '填写正数，方向由上方的流入／流出决定',
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
                const SizedBox(height: 16),
                ReconciliationField(
                  label: '交易时间 · 北京时间',
                  value: time == null
                      ? '请选择交易时间'
                      : reconciliationDate(time!, time: true),
                  icon: Icons.schedule,
                  onTap: () async {
                    final selected = await pickReconciliationTime(
                      context,
                      title: '交易时间',
                      initial: time ?? defaultTime,
                    );
                    if (selected != null && context.mounted) {
                      change(() {
                        time = selected;
                        timeError = false;
                      });
                    }
                  },
                ),
                if (timeError)
                  const ReconciliationNotice('请选择交易时间', warning: true),
                const SizedBox(height: 16),
                TextFormField(
                  controller: balance,
                  decoration: InputDecoration(
                    labelText: '交易后余额（选填）',
                    suffixText: account.currency,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) {
                    try {
                      moneyCents(v);
                      return null;
                    } catch (e) {
                      return '$e';
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '交易描述',
                    hintText: '例如：超市购物、从银行卡充值到支付宝',
                  ),
                ),
              ],
            ),
          ),
        ),
        footer: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              change(() => timeError = time == null);
              if (!form.currentState!.validate() || time == null) return;
              Navigator.pop(
                context,
                StatementRow(
                  id: existing?.id ?? 'manual:${const Uuid().v4()}',
                  accountId: account.id,
                  sourceIds: existing?.sourceIds ?? [],
                  time: time,
                  delta: moneyCents(amount.text)! * (incoming ? 1 : -1),
                  balanceAfter: moneyCents(balance.text),
                  description: description.text.trim(),
                  orderId: existing?.orderId,
                ),
              );
            },
            child: const Text('保存流水'),
          ),
        ),
      ),
    ),
  );
  for (final controller in [amount, balance, description]) {
    controller.dispose();
  }
  return result;
}
