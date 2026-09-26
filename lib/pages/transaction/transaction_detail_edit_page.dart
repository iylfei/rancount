import 'package:beecount/widgets/ui/bee_sheet.dart';
import '../../widgets/biz/transaction_glass.dart';
import '../../styles/liquid_theme.dart';
import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/attachment_service.dart';
import '../../services/data/tx_author_service.dart';
import '../../styles/tokens.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../../widgets/biz/category_selector_dialog.dart';
import '../tag/widgets/tag_selector.dart';
import '../attachment/attachment_preview_page.dart';

/// 明细详情专用的完整编辑页。交易类型和关联退款关系保持不变。
class TransactionDetailEditPage extends ConsumerStatefulWidget {
  const TransactionDetailEditPage({
    super.key,
    required this.transaction,
    this.category,
    this.account,
    this.toAccount,
  });

  final Transaction transaction;
  final Category? category;
  final Account? account;
  final Account? toAccount;

  @override
  ConsumerState<TransactionDetailEditPage> createState() =>
      _TransactionDetailEditPageState();
}

class _TransactionDetailEditPageState
    extends ConsumerState<TransactionDetailEditPage> {
  late final TextEditingController _amount;
  late final TextEditingController _product;
  late final TextEditingController _merchant;
  late final TextEditingController _channel;
  late final TextEditingController _note;
  late DateTime _date;
  Category? _category;
  bool _categoryChanged = false;
  Account? _account;
  Account? _toAccount;
  bool _accountChanged = false;
  bool _toAccountChanged = false;
  late bool _excludeFromStats;
  late bool _excludeFromBudget;
  List<int> _tagIds = [];
  List<String> _tagNames = [];
  bool _saving = false;
  bool _loadingTags = true;

  Transaction get _tx => widget.transaction;
  bool get _isTransfer => _tx.type == 'transfer';
  bool get _isRefund => _tx.refundOfSyncId != null;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _tx.amount.abs().toString());
    _product = TextEditingController(text: _tx.itemDescription ?? '');
    _merchant = TextEditingController(text: _tx.merchant ?? '');
    _channel = TextEditingController(text: _tx.paymentChannel ?? '');
    _note = TextEditingController(text: _tx.note ?? '');
    _date = _tx.happenedAt.toLocal();
    _category = widget.category;
    _account = widget.account;
    _toAccount = widget.toAccount;
    _excludeFromStats = _tx.excludeFromStats;
    _excludeFromBudget = _tx.excludeFromBudget;
    _loadTags();
  }

  Future<void> _loadTags() async {
    final repo = ref.read(repositoryProvider);
    final tags = await repo.getTagsForTransaction(_tx.id);
    final ids = tags.map((tag) => tag.id).toList();
    if (repo is LocalRepository && _tx.syncId != null) {
      final overrides = await (repo.db.select(
        repo.db.transactionTagOverrides,
      )..where((row) => row.transactionSyncId.equals(_tx.syncId!)))
          .get();
      for (final override in overrides) {
        ids.add(syntheticIdForSyncId(override.tagSyncId));
      }
    }
    if (!mounted) return;
    final available = await ref.read(tagsForCurrentLedgerProvider.future);
    if (!mounted) return;
    setState(() {
      _tagIds = ids;
      _tagNames = available
          .where((tag) => ids.contains(tag.id))
          .map((tag) => tag.name)
          .toList();
      _loadingTags = false;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _product.dispose();
    _merchant.dispose();
    _channel.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time == null || !mounted) return;
    setState(
      () => _date = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<List<Account>> _availableAccounts() async {
    final repo = ref.read(repositoryProvider);
    final all = await repo.getAllAccounts();
    if (repo is! LocalRepository) return all;
    final ctx = await repo.db.loadLedgerPickerContext(_tx.ledgerId);
    final filtered = await repo.db.filterAccountsForLedger(all, ctx);
    for (final selected in [_account, _toAccount]) {
      if (selected != null && !filtered.any((a) => a.id == selected.id)) {
        filtered.add(selected);
      }
    }
    return filtered;
  }

  Future<void> _pickAccount({bool destination = false}) async {
    final l10n = AppLocalizations.of(context);
    final accounts = await _availableAccounts();
    if (!mounted) return;
    final selected = await showBeeBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      backgroundColor: LiquidTheme.isActive(context)
          ? Colors.transparent
          : BeeTokens.surfaceElevated(context),
      builder: (sheetContext) => TransactionGlass(
          prominent: true,
          borderRadius: 30,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    destination
                        ? l10n.exportCsvHeaderToAccount
                        : l10n.transactionDetailAccount,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!destination && !_isTransfer)
                  ListTile(
                    title: Text(l10n.accountNone),
                    onTap: () => Navigator.pop(sheetContext, _noAccount),
                  ),
                for (final account in accounts)
                  ListTile(
                    leading: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(account.name),
                    trailing:
                        (destination ? _toAccount : _account)?.id == account.id
                            ? Icon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                    onTap: () => Navigator.pop(sheetContext, account),
                  ),
              ],
            ),
          )),
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (destination) {
        _toAccount = selected as Account;
        _toAccountChanged = true;
      } else {
        _account = identical(selected, _noAccount) ? null : selected as Account;
        _accountChanged = true;
      }
    });
  }

  Future<void> _pickTags() async {
    final ids = await TagSelector.show(context, selectedTagIds: _tagIds);
    if (ids == null || !mounted) return;
    final available = await ref.read(tagsForCurrentLedgerProvider.future);
    if (!mounted) return;
    setState(() {
      _tagIds = ids;
      _tagNames = available
          .where((tag) => ids.contains(tag.id))
          .map((tag) => tag.name)
          .toList();
    });
  }

  Future<String?> _accountSyncId(Account? account) async {
    if (account == null || account.id >= 0) return null;
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return null;
    final ctx = await repo.db.loadLedgerPickerContext(_tx.ledgerId);
    if (ctx?.ledgerSyncId == null) return null;
    final rows = await (repo.db.select(
      repo.db.sharedLedgerAccounts,
    )..where((row) => row.ledgerSyncId.equals(ctx!.ledgerSyncId!)))
        .get();
    for (final row in rows) {
      if (syntheticIdForSyncId(row.syncId) == account.id) return row.syncId;
    }
    return null;
  }

  Future<void> _saveTags() async {
    final repo = ref.read(repositoryProvider);
    final normal = _tagIds.where((id) => id > 0).toList();
    if (normal.isEmpty) {
      await repo.removeAllTagsFromTransaction(_tx.id);
    } else {
      await repo.updateTransactionTags(transactionId: _tx.id, tagIds: normal);
    }
    if (repo is LocalRepository && _tx.syncId != null) {
      await (repo.db.delete(
        repo.db.transactionTagOverrides,
      )..where((row) => row.transactionSyncId.equals(_tx.syncId!)))
          .go();
      final synthetic = _tagIds.where((id) => id < 0).toSet();
      if (synthetic.isNotEmpty) {
        final shared = await repo.db.select(repo.db.sharedLedgerTags).get();
        for (final row in shared) {
          if (!synthetic.contains(syntheticIdForSyncId(row.syncId))) continue;
          await repo.db.into(repo.db.transactionTagOverrides).insert(
                TransactionTagOverridesCompanion.insert(
                  transactionSyncId: _tx.syncId!,
                  tagSyncId: row.syncId,
                  createdAt: DateTime.now().toUtc(),
                ),
              );
        }
      }
    }
    ref.read(tagListRefreshProvider.notifier).state++;
  }

  Future<void> _save() async {
    if (_saving || _loadingTags) return;
    final l10n = AppLocalizations.of(context);
    final parsed = double.tryParse(_amount.text.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.transactionEditInvalidAmount)),
      );
      return;
    }
    if (_isTransfer &&
        (_account == null ||
            _toAccount == null ||
            _account!.id == _toAccount!.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.transactionEditInvalidTransfer)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(repositoryProvider);
      final accountOverride = _accountChanged
          ? await _accountSyncId(_account)
          : _tx.accountSyncIdOverride;
      final toOverride = _toAccountChanged
          ? await _accountSyncId(_toAccount)
          : _tx.toAccountSyncIdOverride;
      if (_accountChanged &&
          _account != null &&
          _account!.id < 0 &&
          accountOverride == null) {
        throw StateError(l10n.transactionEditAccountUnavailable);
      }
      if (_toAccountChanged &&
          _toAccount != null &&
          _toAccount!.id < 0 &&
          toOverride == null) {
        throw StateError(l10n.transactionEditAccountUnavailable);
      }
      final category = _category;
      final categoryOverride = category == null
          ? _tx.categorySyncIdOverride
          : category.id < 0
              ? category.syncId
              : null;
      await repo.updateTransaction(
        id: _tx.id,
        type: _tx.type,
        amount: !_isTransfer && _tx.amount < 0 ? -parsed : parsed,
        categoryId: _isTransfer || _isRefund || _tx.type == 'adjustment'
            ? _tx.categoryId
            : !_categoryChanged
                ? _tx.categoryId
                : category != null && category.id >= 0
                    ? category.id
                    : null,
        categorySyncIdOverride:
            _isTransfer || _isRefund || _tx.type == 'adjustment'
                ? _tx.categorySyncIdOverride
                : categoryOverride,
        note: _note.text.trim(),
        merchant: _merchant.text.trim(),
        itemDescription: _product.text.trim(),
        paymentChannel: _channel.text.trim(),
        happenedAt: _date,
        accountId: _accountChanged
            ? d.Value<int?>(
                _account != null && _account!.id >= 0 ? _account!.id : null,
              )
            : null,
        accountSyncIdOverride: accountOverride,
        toAccountSyncIdOverride:
            _isTransfer ? toOverride : _tx.toAccountSyncIdOverride,
        excludeFromStats: _excludeFromStats,
        excludeFromBudget: _excludeFromBudget,
      );
      if (_isTransfer && _toAccountChanged) {
        await repo.updateTransactionFields(
          id: _tx.id,
          toAccountId: d.Value<int?>(
            _toAccount!.id >= 0 ? _toAccount!.id : null,
          ),
          toAccountSyncIdOverride: toOverride,
          writeToAccountSyncIdOverride: true,
          writeAccountSyncIdOverride: false,
        );
      }
      await _saveTags();
      await TxAuthorService.markEdited(ref, _tx.id);
      ref.invalidate(countsForLedgerProvider(_tx.ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      ref.read(budgetRefreshProvider.notifier).state++;
      PostProcessor.sync(ref, ledgerId: _tx.ledgerId);
      if (mounted) updateAppWidget(ref, context);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.categorySaveError}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(BuildContext context, List<Widget> children) => TransactionPanel(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BeeTokens.borderStrong(context)),
        ),
        child: Column(children: children),
      );

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: BeeTokens.surfaceInput(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _choice(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    VoidCallback? onTap,
  ) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          title,
          style:
              TextStyle(color: BeeTokens.textSecondary(context), fontSize: 13),
        ),
        subtitle: Text(
          value,
          style: TextStyle(color: BeeTokens.textPrimary(context), fontSize: 16),
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final typeLabel = _isTransfer
        ? l10n.transferTitle
        : _tx.type == 'income'
            ? l10n.categoryIncome
            : l10n.categoryExpense;
    return TransactionScaffold(
      backgroundColor: LiquidTheme.isActive(context)
          ? Colors.transparent
          : BeeTokens.scaffoldBackground(context),
      appBar: AppBar(
        title: Text(l10n.transactionEditTitle),
        backgroundColor: LiquidTheme.isActive(context)
            ? Colors.transparent
            : BeeTokens.scaffoldBackground(context),
        actions: [
          TextButton(
            onPressed: _saving || _loadingTags ? null : _save,
            child: Text(
              l10n.commonSave,
              style: TextStyle(color: primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TransactionPanel(
            prominent: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: primary.withValues(
                alpha: BeeTokens.isDark(context) ? 0.18 : 0.09,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: primary.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: TextStyle(
                    fontSize: LiquidTheme.isActive(context) ? 40 : 34,
                    fontWeight: FontWeight.w700,
                    color: BeeTokens.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    prefixText:
                        '${NumberFormat.simpleCurrency(name: _tx.currencyCode ?? 'CNY').currencySymbol}  ',
                    hintText: '0.00',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          _card(context, [
            if (!_isTransfer && _tx.type != 'adjustment')
              _choice(
                context,
                Icons.category_outlined,
                l10n.transactionDetailCategory,
                _category?.name ?? l10n.commonUncategorized,
                _isRefund
                    ? null
                    : () async {
                        final selected = await showCategorySelector(
                          context,
                          type: _tx.type,
                          currentCategoryId: _category?.id,
                          includeParentCategories: true,
                        );
                        if (selected != null && mounted) {
                          setState(() {
                            _category = selected;
                            _categoryChanged = true;
                          });
                        }
                      },
              ),
            _choice(
              context,
              Icons.account_balance_wallet_outlined,
              _isTransfer
                  ? l10n.exportCsvHeaderFromAccount
                  : l10n.transactionDetailAccount,
              _account?.name ?? l10n.accountNone,
              () => _pickAccount(),
            ),
            if (_isTransfer)
              _choice(
                context,
                Icons.south_west_rounded,
                l10n.exportCsvHeaderToAccount,
                _toAccount?.name ?? l10n.accountNone,
                () => _pickAccount(destination: true),
              ),
            _choice(
              context,
              Icons.calendar_today_outlined,
              l10n.transactionDetailTime,
              DateFormat('yyyy-MM-dd HH:mm').format(_date),
              _pickDate,
            ),
          ]),
          _card(context, [
            _field(context, l10n.transactionDetailProduct, _product),
            _field(context, l10n.transactionDetailMerchant, _merchant),
            _field(context, l10n.transactionDetailPaymentChannel, _channel),
            _field(context, l10n.transactionDetailNote, _note, maxLines: 3),
          ]),
          _card(context, [
            _choice(
              context,
              Icons.sell_outlined,
              l10n.transactionDetailTags,
              _loadingTags
                  ? '…'
                  : _tagNames.isEmpty
                      ? l10n.commonEmpty
                      : _tagNames.join(' · '),
              _loadingTags ? null : _pickTags,
            ),
            _choice(
              context,
              Icons.attach_file,
              l10n.transactionDetailAttachments,
              l10n.commonEdit,
              () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttachmentPreviewPage.fromTransaction(
                      transactionId: _tx.id,
                      allowAdd: true,
                    ),
                  ),
                );
                ref.read(attachmentListRefreshProvider.notifier).state++;
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.txFlagExcludeFromStats),
              value: _excludeFromStats,
              onChanged: (value) => setState(() => _excludeFromStats = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.txFlagExcludeFromBudget),
              value: _excludeFromBudget,
              onChanged: (value) => setState(() => _excludeFromBudget = value),
            ),
          ]),
        ],
      ),
    );
  }
}

/// 底部账户列表中“清空账户”的显式选择值。
const _noAccount = _NoAccount();

class _NoAccount {
  const _NoAccount();
}
