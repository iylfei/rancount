import 'package:flutter/material.dart';

import '../../services/reconciliation/reconciliation_models.dart';
import 'reconciliation_ui.dart';

class ReconciliationQuestionsView extends StatelessWidget {
  final ReconciliationSession session;
  final bool locked;
  final ValueChanged<Json> onAnswer;
  const ReconciliationQuestionsView({
    super.key,
    required this.session,
    required this.locked,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReconciliationHeading(
        '需要补充的信息（${session.questions.length} 项）',
        description: '确认后重新分析，已识别流水会保留。',
      ),
      for (final question in session.questions)
        ReconciliationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question['text'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (question['hint'] != null) Text(question['hint'] as String),
              for (final row in session.rows.where(
                (r) => List<String>.from(
                  question['evidenceIds'] ?? [],
                ).contains(r.id),
              )) ...[
                const SizedBox(height: 8),
                Text(
                  '${session.accounts.singleWhere((a) => a.id == row.accountId).name} · '
                  '${row.time == null ? '时间待确认' : reconciliationDate(row.time!, time: row.timePrecision != 'day')}\n'
                  '${row.delta == null ? '金额待确认' : moneyText(row.delta!)} · ${row.description}',
                ),
              ],
              if (!session.applied) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: locked ? null : () => onAnswer(question),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(
                    question['kind'] == 'funding'
                        ? '确认资金账户'
                        : question['kind'] == 'purpose'
                        ? '补充交易信息'
                        : '确认流水范围与记账起点',
                  ),
                ),
              ],
            ],
          ),
        ),
    ],
  );
}
