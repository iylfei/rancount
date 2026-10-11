import 'package:flutter/material.dart';

import '../../services/reconciliation/reconciliation_models.dart';
import '../../utils/beijing_time.dart';
import 'reconciliation_ui.dart';

Future<Json?> editReconciliationEvidence(
  BuildContext context,
  ReconciliationSession session,
  ReconciliationAccount account,
) async {
  final until = account.balanceAt.isBefore(session.end)
      ? account.balanceAt
      : session.end;
  var initial = account.initialBalanceAt;
  final initialStart = initial != null && initial.isAfter(session.start)
      ? initial
      : session.start;
  var full = account.covers(initialStart, until);
  return showReconciliationSheet<Json>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) {
        final from = initial != null && initial!.isAfter(session.start)
            ? initial!
            : session.start;
        return ReconciliationSheet(
          title: '流水范围与记账起点',
          subtitle: account.name,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReconciliationField(
                  label: '初始余额对应日期（选填）',
                  icon: Icons.event_outlined,
                  value: initial == null
                      ? '尚未确认'
                      : reconciliationDate(initial!),
                  hint: '账户创建时填写的余额对应哪一天；只作为核对起点，不修改余额金额',
                  onTap: () async {
                    final selected = initial ?? session.start;
                    final date = await showDatePicker(
                      context: context,
                      initialDate: beijingTime(
                        selected.isAfter(until) ? until : selected,
                      ),
                      firstDate: DateTime(1970),
                      lastDate: beijingTime(until),
                    );
                    if (date != null && context.mounted) {
                      change(() {
                        initial = beijingDate(
                          date.year,
                          date.month,
                          date.day,
                        ).toUtc();
                        full = false;
                      });
                    }
                  },
                ),
                if (initial != null)
                  TextButton(
                    onPressed: () => change(() {
                      initial = null;
                      full = false;
                    }),
                    child: const Text('清除日期，保留待确认'),
                  ),
                const SizedBox(height: 16),
                Text('需要覆盖的期间', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '${reconciliationDate(from, time: true)}\n至 ${reconciliationDate(until, time: true)}',
                ),
                const SizedBox(height: 12),
                RadioListTile<bool>(
                  value: true,
                  groupValue: full,
                  title: const Text('已提供这个期间的全部流水'),
                  subtitle: const Text('检查翻页、筛选条件，以及每笔实际付款账户'),
                  onChanged: (v) => change(() => full = v!),
                ),
                RadioListTile<bool>(
                  value: false,
                  groupValue: full,
                  title: const Text('只提供了部分流水／暂未确认'),
                  subtitle: const Text('仍可逐笔核对，余额差额暂不归因到历史'),
                  onChanged: (v) => change(() => full = v!),
                ),
              ],
            ),
          ),
          footer: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, {
                'initialBalanceAt': initial?.toIso8601String(),
                'coverageStart': full ? from.toIso8601String() : null,
                'coverageEnd': full ? until.toIso8601String() : null,
              }),
              child: const Text('保存核对信息'),
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> answerReconciliationQuestion(
  BuildContext context,
  Json question,
  String previous,
) async {
  final answer = TextEditingController(text: previous);
  final form = GlobalKey<FormState>();
  final result = await showReconciliationSheet<String>(
    context,
    builder: (context) => ReconciliationSheet(
      title: '补充交易信息',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question['text'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (question['hint'] != null) ...[
                const SizedBox(height: 12),
                Text(question['hint'] as String),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: answer,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '你核实的信息',
                  hintText: '例如：公司报销到账，其中一部分转交给同事',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请补充信息后保存' : null,
              ),
            ],
          ),
        ),
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, answer.text.trim());
            }
          },
          child: const Text('保存，重新分析时使用'),
        ),
      ),
    ),
  );
  answer.dispose();
  return result;
}
