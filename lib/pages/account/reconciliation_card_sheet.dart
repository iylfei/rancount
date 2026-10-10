import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/reconciliation/reconciliation_models.dart';
import 'reconciliation_ui.dart';

Future<Map<int, String?>?> selectReconciliationCards(
  BuildContext context,
  List<ReconciliationAccount> accounts,
) async {
  final cards = accounts
      .where((a) => ['bank_card', 'credit_card'].contains(a.type))
      .toList();
  final controllers = {
    for (final a in cards) a.id: TextEditingController(text: a.cardLast4 ?? ''),
  };
  final form = GlobalKey<FormState>();
  final result = await showReconciliationSheet<Map<int, String?>>(
    context,
    builder: (context) => ReconciliationSheet(
      title: '银行卡流水归属',
      subtitle: '同一张图可以上传到多个账户，按交易用卡尾号分别核对',
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ReconciliationNotice('混合显示多张银行卡时，填写截图里的交易用卡尾号。其他账户可留空。'),
            for (final a in cards)
              ReconciliationCard(
                child: TextFormField(
                  controller: controllers[a.id],
                  decoration: InputDecoration(
                    labelText: a.name,
                    hintText: '卡号后四位（选填）',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  validator: (v) =>
                      v!.isNotEmpty && v.length != 4 ? '请填写完整的四位尾号' : null,
                ),
              ),
          ],
        ),
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(context, {
              for (final a in cards)
                a.id: controllers[a.id]!.text.isEmpty
                    ? null
                    : controllers[a.id]!.text,
            });
          },
          child: const Text('保存卡尾号'),
        ),
      ),
    ),
  );
  for (final c in controllers.values) {
    c.dispose();
  }
  return result;
}
