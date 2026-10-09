import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/reconciliation/reconciliation_models.dart';
import 'reconciliation_ui.dart';

class ReconciliationSetupView extends StatelessWidget {
  final ReconciliationSession session;
  final bool locked;
  final VoidCallback onAccounts;
  final VoidCallback onPeriod;
  const ReconciliationSetupView({
    super.key,
    required this.session,
    required this.locked,
    required this.onAccounts,
    required this.onPeriod,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ReconciliationHeading(
        '先确定要核对的账户和期间',
        description: '选择近期流水有交集的资金账户，可以一起检查账户之间的转账。',
      ),
      ReconciliationCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReconciliationField(
              label: '对账账户',
              icon: Icons.account_balance_wallet_outlined,
              value: session.accounts.isEmpty
                  ? '请选择一个或多个账户'
                  : session.accounts.map((a) => a.name).join('、'),
              hint: session.accounts.isEmpty
                  ? '支持支付宝、微信、银行卡和现金'
                  : '已选择 ${session.accounts.length} 个账户',
              onTap: locked ? null : onAccounts,
            ),
            const SizedBox(height: 16),
            ReconciliationField(
              label: '对账期间',
              icon: Icons.date_range_outlined,
              value:
                  '${reconciliationDate(session.start)} 至 ${reconciliationDate(session.end)}',
              hint: '截止 ${reconciliationDate(session.end, time: true)} · 北京时间',
              onTap: locked ? null : onPeriod,
            ),
          ],
        ),
      ),
      const ReconciliationNotice('下一步按账户添加流水截图，并填写实际余额。修改建议会先展示给你审核。'),
    ],
  );
}

class ReconciliationAccountInput extends StatelessWidget {
  final ReconciliationSession session;
  final ReconciliationAccount account;
  final bool locked;
  final String? balanceError;
  final VoidCallback onImages;
  final VoidCallback onTime;
  final VoidCallback onManual;
  final ValueChanged<String> onBalance;
  final ValueChanged<bool> onComplete;
  final ValueChanged<Json> onRemoveImage;
  final ValueChanged<StatementRow> onEditRow;
  final ValueChanged<StatementRow> onRemoveRow;
  const ReconciliationAccountInput({
    super.key,
    required this.session,
    required this.account,
    required this.locked,
    required this.onImages,
    required this.onTime,
    required this.onManual,
    required this.onBalance,
    required this.onComplete,
    required this.onRemoveImage,
    required this.onEditRow,
    required this.onRemoveRow,
    this.balanceError,
  });

  @override
  Widget build(BuildContext context) {
    final sources = session.sources
        .where((s) => s['accountId'] == account.id)
        .toList();
    final rows = session.rows.where((r) => r.accountId == account.id).toList()
      ..sort(
        (a, b) =>
            (b.time ?? DateTime(2000)).compareTo(a.time ?? DateTime(2000)),
      );
    final empty = sources.isEmpty && rows.isEmpty;
    return ReconciliationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                account.currency,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            empty
                ? '尚未添加流水资料'
                : '${sources.length} 张截图 · ${rows.length} 条已识别／补充流水',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: locked ? null : onImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('添加流水截图'),
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < sources.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _ScreenshotTile(
                        source: sources[i],
                        number: i + 1,
                        onDelete: locked
                            ? null
                            : () => onRemoveImage(sources[i]),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey(
              '${session.id}:${account.id}:balance:${account.balanceAt}',
            ),
            enabled: !locked,
            initialValue: account.actualBalance == null
                ? ''
                : moneyText(account.actualBalance!),
            decoration: InputDecoration(
              labelText: '实际余额（选填）',
              suffixText: account.currency,
              hintText: '查看该账户后填写',
              errorText: balanceError,
              helperText: '完整流水中有交易后余额时，可以留空',
              helperMaxLines: 2,
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: onBalance,
          ),
          const SizedBox(height: 16),
          ReconciliationField(
            label: '余额对应时间 · 北京时间',
            value: reconciliationDate(account.balanceAt, time: true),
            icon: Icons.schedule,
            onTap: locked ? null : onTime,
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(empty ? '这个期间内没有余额变动' : '已添加这个期间的全部流水'),
            subtitle: Text(
              empty ? '没有交易时，请填写上方实际余额。' : '从开始日期到余额对应时间，包含充值、提现、转账和退款。',
            ),
            value: account.complete,
            onChanged: locked ? null : (value) => onComplete(value!),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: locked ? null : onManual,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('手动补充一条流水'),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              key: PageStorageKey('${session.id}:${account.id}:rows'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('检查流水（${rows.length} 条）'),
              subtitle: const Text('金额、时间或描述不对时可点开修改'),
              children: [
                for (final row in rows) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      row.description.isEmpty ? '未识别交易描述' : row.description,
                    ),
                    subtitle: Text(
                      '${row.time == null ? '时间待确认' : reconciliationDate(row.time!, time: true)}'
                      '${row.balanceAfter == null ? '' : '\n交易后余额 ${moneyText(row.balanceAfter!)}'}'
                      '${row.warnings.isEmpty ? '' : '\n${row.warnings.join('；')}'}',
                    ),
                    onTap: locked ? null : () => onEditRow(row),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          row.delta == null
                              ? '金额待确认'
                              : '${row.delta! > 0 ? '+' : ''}${moneyText(row.delta!)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (!locked)
                          Text(
                            '点击编辑',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  if (!locked)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => onRemoveRow(row),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('移除此条'),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScreenshotTile extends StatelessWidget {
  final Json source;
  final int number;
  final VoidCallback? onDelete;
  const _ScreenshotTile({
    required this.source,
    required this.number,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Column(
      children: [
        Material(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showReconciliationSheet<void>(
              context,
              builder: (context) => ReconciliationSheet(
                title: '截图 $number',
                subtitle: '双指缩放查看原始流水',
                body: InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      File(source['path']),
                      errorBuilder: (_, __, ___) => const Text('截图文件不可用'),
                    ),
                  ),
                ),
                footer: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回资料'),
                  ),
                ),
              ),
            ),
            child: Image.file(
              File(source['path']),
              width: 92,
              height: 112,
              cacheWidth: (92 * MediaQuery.devicePixelRatioOf(context)).round(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 112,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '截图 $number${source['recognized'] == true ? ' · 已识别' : ''}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        if (onDelete != null)
          TextButton(onPressed: onDelete, child: const Text('移除')),
      ],
    ),
  );
}
