import 'package:flutter/material.dart';

import '../../data/db.dart' as db;
import '../../services/reconciliation/reconciliation_engine.dart';
import '../../services/reconciliation/reconciliation_models.dart';
import '../../services/reconciliation/reconciliation_store.dart';
import 'reconciliation_ui.dart';

class ReconciliationResultView extends StatelessWidget {
  final ReconciliationSession session;
  final ReconciliationSnapshot snapshot;
  final bool locked;
  final ValueChanged<Json> onSelect;
  final void Function(Json proposal, Json mutation) onEdit;
  final VoidCallback onStatements;
  const ReconciliationResultView({
    super.key,
    required this.session,
    required this.snapshot,
    required this.locked,
    required this.onSelect,
    required this.onEdit,
    required this.onStatements,
  });

  @override
  Widget build(BuildContext context) {
    final reports = reconciliationReports(
      session,
      snapshot.transactions,
      snapshot.initialBalances,
      proposals: session.applied ? [] : null,
    );
    final selected = session.proposals
        .where((p) => p['selected'] == true)
        .length;
    final stale =
        !session.applied && session.fingerprint != snapshot.fingerprint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReconciliationHeading(
          session.applied ? '本次修改已应用' : '先核对结果，再选择修改建议',
          description: session.applied
              ? '下面保留本次分析和修改内容。'
              : '找到 ${session.proposals.length} 组建议，已选 $selected 组。选择后可查看余额变化。',
        ),
        if (stale)
          const ReconciliationNotice('记账数据已变化，请返回流水资料重新分析。', warning: true),
        if (session.summary.isNotEmpty)
          ReconciliationCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('分析说明', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(session.summary),
              ],
            ),
          ),
        const ReconciliationHeading(
          '各账户余额',
          description: '同一账户的账面余额和实际余额按相同时间核对。',
        ),
        for (final report in reports)
          _BalanceReport(report: report, applied: session.applied),
        if (session.issues.isNotEmpty)
          ReconciliationCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.info_outline),
              title: Text('需要检查（${session.issues.length} 项）'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final issue in session.issues)
                  ReconciliationNotice(issue, warning: true),
              ],
            ),
          ),
        ReconciliationHeading(
          '修改建议',
          description: session.proposals.isEmpty
              ? '本次没有可应用的修改建议。请结合分析说明和待检查事项核对资料。'
              : '点开明细核对原记录、修改内容和截图依据，再勾选要应用的建议。',
        ),
        for (final proposal in session.proposals)
          _ProposalCard(
            session: session,
            snapshot: snapshot,
            proposal: proposal,
            locked: locked,
            onSelect: () => onSelect(proposal),
            onEdit: (mutation) => onEdit(proposal, mutation),
          ),
        if (!session.applied)
          OutlinedButton.icon(
            onPressed: locked ? null : onStatements,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('返回流水资料／重新分析'),
          ),
        const SizedBox(height: 16),
        if (session.applied)
          const ReconciliationNotice('撤销会恢复本次修改前的记录。如果记录后来有变化，会提示你检查。'),
      ],
    );
  }
}

class _BalanceReport extends StatelessWidget {
  final AccountReconciliationReport report;
  final bool applied;
  const _BalanceReport({required this.report, required this.applied});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return ReconciliationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${r.account.name} · ${r.account.currency}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            reconciliationDate(r.account.balanceAt, time: true),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _ValueRow('账面余额', moneyText(r.bookBalance)),
          _ValueRow(
            '实际余额',
            r.actualBalance == null ? '未提供' : moneyText(r.actualBalance!),
          ),
          if (r.actualBalance != null)
            _ValueRow('当前差额', moneyText(r.actualBalance! - r.bookBalance)),
          if (!applied) ...[
            const Divider(height: 24),
            _ValueRow(
              '应用已选建议后',
              moneyText(r.projectedBalance),
              highlighted: true,
            ),
            if (r.actualBalance != null)
              _ValueRow(
                '预计剩余差额',
                moneyText(r.actualBalance! - r.projectedBalance),
              ),
          ],
          if (r.periodDifference != null) ...[
            const Divider(height: 24),
            _ValueRow('期间流水差额', moneyText(r.periodDifference!)),
          ],
          if (r.openingDifference != null && r.openingDifference != 0)
            ReconciliationNotice(
              '开始日期之前已有差额 ${moneyText(r.openingDifference!)}。需要更早的流水证据，暂不调整余额。',
              warning: true,
            ),
          for (final warning in r.warnings)
            ReconciliationNotice(warning, warning: true),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlighted;
  const _ValueRow(this.label, this.value, {this.highlighted = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: highlighted ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProposalCard extends StatelessWidget {
  final ReconciliationSession session;
  final ReconciliationSnapshot snapshot;
  final Json proposal;
  final bool locked;
  final VoidCallback onSelect;
  final ValueChanged<Json> onEdit;
  const _ProposalCard({
    required this.session,
    required this.snapshot,
    required this.proposal,
    required this.locked,
    required this.onSelect,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final mutations = jsonObjects(p['mutations']);
    final ids = List<String>.from(p['evidenceIds']);
    final rows = session.rows.where((r) => ids.contains(r.id)).toList();
    return ReconciliationCard(
      selected: p['selected'] == true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(p['title']?.toString() ?? '修改建议'),
            subtitle: Text(
              session.applied
                  ? (p['selected'] == true ? '已应用' : '未应用')
                  : p['certainty'] == 'supported'
                  ? '有流水依据，请核对后选择'
                  : '需要你进一步确认',
            ),
            value: p['selected'] == true,
            onChanged: locked || p['validationError'] != null
                ? null
                : (_) => onSelect(),
          ),
          if (p['reason']?.toString().isNotEmpty == true)
            Text(p['reason'].toString()),
          if (p['validationError'] != null)
            ReconciliationNotice(
              '暂不可应用：${p['validationError']}',
              warning: true,
            ),
          ExpansionTile(
            key: PageStorageKey('${session.id}:${p['id']}:details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('查看修改明细（${mutations.length} 笔）'),
            children: [
              for (final m in mutations) ...[
                _MutationComparison(
                  mutation: m,
                  snapshot: snapshot,
                  audit: session.applied && p['selected'] == true
                      ? session.audit
                      : null,
                ),
                if (m['after'] != null && !session.applied)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: locked ? null : () => onEdit(m),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('编辑这条建议'),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '流水依据',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              for (final row in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${session.accounts.where((a) => a.id == row.accountId).firstOrNull?.name ?? ''} · ${row.delta == null ? '金额待确认' : moneyText(row.delta!)}',
                  ),
                  subtitle: Text(
                    '${row.time == null ? '时间待确认' : reconciliationDate(row.time!, time: true)}\n${row.description}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MutationComparison extends StatelessWidget {
  final Json mutation;
  final ReconciliationSnapshot snapshot;
  final Json? audit;
  const _MutationComparison({
    required this.mutation,
    required this.snapshot,
    this.audit,
  });

  @override
  Widget build(BuildContext context) {
    // After applying, the snapshot contains the new records. Read originals
    // from the retained audit rather than mislabelling current data as old.
    Json? before;
    if (audit != null) {
      final original = jsonObjects(audit!['changes'])
          .where(
            (change) =>
                change['before'] != null &&
                jsonObject(change['before'])['id'] == mutation['transactionId'],
          )
          .firstOrNull?['before'];
      if (original != null) {
        before = reconciliationTransaction(
          db.Transaction.fromJson(jsonObject(original)),
        );
      }
    } else {
      before = snapshot.transactions
          .where((t) => t['id'] == mutation['transactionId'])
          .firstOrNull;
    }
    final after = mutation['after'] == null
        ? null
        : jsonObject(mutation['after']);
    Widget box(
      String label,
      Json? tx,
      String empty, {
      bool accent = false,
    }) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .06)
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: .03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: .7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (tx == null)
            Text(empty)
          else
            _TransactionDetails(tx: tx, snapshot: snapshot),
        ],
      ),
    );
    return Column(
      children: [
        box('原记录', before, '账本中没有这条记录'),
        box(after == null ? '建议操作' : '修改后', after, '删除这条记录', accent: true),
      ],
    );
  }
}

class _TransactionDetails extends StatelessWidget {
  final Json tx;
  final ReconciliationSnapshot snapshot;
  const _TransactionDetails({required this.tx, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    String account(Object? id) =>
        snapshot.accounts.where((a) => a.id == id).firstOrNull?.name ?? '未指定账户';
    final type = switch (tx['type']) {
      'expense' => (tx['amountCents'] as int) < 0 ? '退款' : '支出',
      'income' => '收入',
      'transfer' => '转账',
      _ => '${tx['type']}',
    };
    final details = [
      tx['merchant'],
      tx['itemDescription'],
      tx['note'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$type ${moneyText((tx['amountCents'] as int).abs())}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${account(tx['accountId'])}${tx['type'] == 'transfer' ? ' → ${account(tx['toAccountId'])}' : ''}',
        ),
        Text(reconciliationDate(evidenceTime(tx['happenedAt'])!, time: true)),
        Text(
          '${snapshot.ledgers.where((l) => l.id == tx['ledgerId']).firstOrNull?.name ?? '未指定账本'} · '
          '${snapshot.categories.where((c) => c.id == tx['categoryId']).firstOrNull?.name ?? '未分类'}',
        ),
        if (details.isNotEmpty) Text(details),
        if (tx['refundOfSyncId'] != null || tx['refundOfMutationId'] != null)
          const Text('关联原支出退款'),
      ],
    );
  }
}
