import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../styles/liquid_theme.dart';
import 'amount_text.dart';

/// 明细首页的只读交易详情。编辑动作交给列表页关闭弹层后执行。
class TransactionDetailSheet extends StatelessWidget {
  final Transaction transaction;
  final String title;
  final String? categoryName;
  final String? accountName;
  final String? toAccountName;
  final List<String> tags;
  final int attachmentCount;
  final bool hideAmounts;
  final VoidCallback onEdit;

  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    required this.title,
    this.categoryName,
    this.accountName,
    this.toAccountName,
    this.tags = const [],
    this.attachmentCount = 0,
    required this.hideAmounts,
    required this.onEdit,
  });

  String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: LiquidTheme.isActive(context) ? 15 : 13,
                color: BeeTokens.textSecondary(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: LiquidTheme.isActive(context) ? 16 : 14,
                height: LiquidTheme.isActive(context) ? 1.4 : null,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liquid = LiquidTheme.isActive(context);
    final l10n = AppLocalizations.of(context);
    final isTransfer = transaction.type == 'transfer';
    final account = _nonBlank(accountName);
    final toAccount = _nonBlank(toAccountName);
    final accountDisplay = isTransfer && toAccount != null
        ? (account == null ? toAccount : '$account → $toAccount')
        : account;
    final flags = [
      if (transaction.excludeFromStats) l10n.txFlagExcludedTag,
      if (transaction.excludeFromBudget) l10n.txFlagBudgetExcludedTag,
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: liquid ? 0 : MediaQuery.sizeOf(context).height * 0.72,
          maxHeight: MediaQuery.sizeOf(context).height * (liquid ? 0.85 : 0.72),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: l10n.commonClose,
                  ),
                  Expanded(
                    child: Text(
                      l10n.transactionDetailTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.commonEdit,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AmountText(
                    value: transaction.type == 'adjustment'
                        ? transaction.amount
                        : transaction.type == 'expense'
                        ? -transaction.amount
                        : transaction.amount,
                    hide: hideAmounts,
                    signed: !isTransfer,
                    showCurrency: true,
                    currencyCode: transaction.currencyCode,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: BeeTokens.border(context), height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_nonBlank(transaction.itemDescription) != null)
                    _detailRow(
                      context,
                      l10n.transactionDetailProduct,
                      transaction.itemDescription!.trim(),
                    ),
                  if (_nonBlank(categoryName) != null)
                    _detailRow(
                      context,
                      l10n.transactionDetailCategory,
                      categoryName!.trim(),
                    ),
                  if (_nonBlank(transaction.merchant) != null)
                    _detailRow(
                      context,
                      l10n.transactionDetailMerchant,
                      transaction.merchant!.trim(),
                    ),
                  if (_nonBlank(transaction.paymentChannel) != null)
                    _detailRow(
                      context,
                      l10n.transactionDetailPaymentChannel,
                      transaction.paymentChannel!.trim(),
                    ),
                  if (_nonBlank(accountDisplay) != null)
                    _detailRow(
                      context,
                      l10n.transactionDetailAccount,
                      accountDisplay!.trim(),
                    ),
                  _detailRow(
                    context,
                    l10n.transactionDetailTime,
                    DateFormat(
                      'yyyy-MM-dd HH:mm:ss',
                    ).format(transaction.happenedAt.toLocal()),
                  ),
                  if (_nonBlank(transaction.note) != null)
                    _detailRow(
                      context,
                      l10n.transactionDetailNote,
                      transaction.note!.trim(),
                    ),
                  if (tags.isNotEmpty)
                    _detailRow(
                      context,
                      l10n.transactionDetailTags,
                      tags.join(' · '),
                    ),
                  if (attachmentCount > 0)
                    _detailRow(
                      context,
                      l10n.transactionDetailAttachments,
                      '$attachmentCount',
                    ),
                  if (flags.isNotEmpty)
                    _detailRow(
                      context,
                      l10n.transactionDetailFlags,
                      flags.join(' · '),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
