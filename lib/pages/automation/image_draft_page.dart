import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../ai/core/bill_info.dart';
import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/ai_chat_providers.dart';
import '../../services/billing/image_draft_service.dart';
import '../../services/billing/image_vision_config.dart';
import '../../services/billing/background_sync_retry.dart';
import '../../services/billing/post_processor.dart';
import '../../services/data/tag_seed_service.dart';
import '../transaction/transaction_editor_page.dart';

class ImageDraftPage extends ConsumerStatefulWidget {
  final File? image;
  final bool ownsImage;
  final ImageDraftSession? existing;

  const ImageDraftPage(
      {super.key, this.image, this.ownsImage = false, this.existing});

  @override
  ConsumerState<ImageDraftPage> createState() => _ImageDraftPageState();
}

class _ImageDraftPageState extends ConsumerState<ImageDraftPage> {
  final ImageDraftStore _store = ImageDraftStore();
  ImageDraftSession? _session;
  File? _image;
  bool _ownsCurrentImage = false;
  bool _recognizing = false;
  bool _saving = false;
  bool _confirmPending = false;
  String? _error;
  Future<void> _writes = Future.value();

  String _label(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _session = widget.existing;
    _image = widget.image;
    _ownsCurrentImage = widget.ownsImage;
    if (_session == null && _image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recognize());
    }
  }

  Future<void> _deleteOwnedImage() async {
    final image = _image;
    _image = null;
    if (!_ownsCurrentImage || image == null) return;
    try {
      final cache = await getTemporaryDirectory();
      if (!p.isWithin(cache.path, p.normalize(image.path))) return;
      if (await image.exists()) await image.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (!_recognizing) unawaited(_deleteOwnedImage());
    super.dispose();
  }

  Future<void> _recognize() async {
    final image = _image;
    if (image == null || _recognizing) return;
    setState(() {
      _recognizing = true;
      _error = null;
    });
    try {
      if (!(await const ImageVisionConfigStore().load()).isComplete) {
        throw StateError('vision-not-configured');
      }
      final ledger = await ref.read(currentLedgerProvider.future);
      if (ledger == null) throw StateError('no-ledger');
      final service = ImageDraftService(
        repository: ref.read(repositoryProvider),
        store: _store,
      );
      final result = await service.recognize(image, ledger.id);
      if (!mounted) return;
      if (result.entries.isEmpty) {
        setState(() => _error = _label('没有识别到账单，可重试或手动填写',
            'No transactions found. Retry or enter one manually.'));
      } else {
        setState(() => _session = result);
        // The draft contains only text; the captured or shared temp image is done.
        await _deleteOwnedImage();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _label('识别失败。请到截图记账设置检查视觉接口后重试',
            'Recognition failed. Check the vision API in Screenshot billing settings.'));
      }
    } finally {
      if (mounted) setState(() => _recognizing = false);
      if (!mounted) await _deleteOwnedImage();
    }
  }

  void _update(int index, ImageDraftEntry Function(ImageDraftEntry) change) {
    final current = _session;
    if (current == null || index < 0 || index >= current.entries.length) return;
    if (current.entries[index].saved) return;
    final entries = [...current.entries];
    entries[index] = change(entries[index]);
    final updated = current.copyWith(entries: entries);
    setState(() => _session = updated);
    _writes = _writes.then((_) => _store.put(updated));
  }

  void _edit(int index, String field, String value) {
    _update(index, (entry) {
      final json = entry.bill.toJson();
      if (field == 'amount') {
        final parsed = double.tryParse(value);
        json[field] = parsed == null
            ? null
            : entry.bill.type == BillType.expense
                ? -parsed.abs()
                : parsed.abs();
      } else if (field == 'type') {
        json[field] = value;
        final amount = entry.bill.amount;
        if (amount != null) {
          json['amount'] = value == 'expense' ? -amount.abs() : amount.abs();
        }
      } else {
        json[field] = value;
      }
      return entry.copyWith(bill: BillInfo.fromJson(json));
    });
  }

  String? _missing(BillInfo bill) {
    if (bill.type == null) return _label('交易类型', 'type');
    if (bill.amount == null ||
        !bill.amount!.isFinite ||
        bill.amount!.abs() <= 0) {
      return _label('金额', 'amount');
    }
    if (bill.time == null) return _label('日期时间', 'date and time');
    if (bill.type == BillType.transfer) {
      if ((bill.fromAccount ?? '').trim().isEmpty) {
        return _label('转出账户', 'source account');
      }
      if ((bill.toAccount ?? '').trim().isEmpty) {
        return _label('转入账户', 'destination account');
      }
    } else {
      if ((bill.category ?? '').trim().isEmpty) return _label('分类', 'category');
      if ((bill.account ?? '').trim().isEmpty) return _label('资金账户', 'account');
    }
    return null;
  }

  Future<bool> _isPossibleDuplicate(BillInfo bill, int ledgerId) async {
    final time = bill.time!;
    final rows =
        await ref.read(repositoryProvider).getTransactionsByLedgerInRange(
              ledgerId: ledgerId,
              start: time.subtract(const Duration(minutes: 2)),
              end: time.add(const Duration(minutes: 2)),
            );
    return rows.any((Transaction tx) =>
        tx.type == bill.type!.name &&
        (tx.amount - bill.amount!.abs()).abs() < 0.01);
  }

  Future<void> _confirm() async {
    if (_saving || _confirmPending) return;
    final session = _session;
    if (session == null) return;
    _confirmPending = true;
    try {
      final selected = session.entries
          .where((entry) => entry.selected && !entry.saved)
          .toList();
      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_label('请先勾选账单', 'Select at least one transaction')),
        ));
        return;
      }
      for (final entry in selected) {
        final missing = _missing(entry.bill);
        if (missing != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_label('请补全：$missing', 'Please fill in: $missing')),
          ));
          return;
        }
      }
      final accounts = await ref.read(repositoryProvider).getAllAccounts();
      final categories = await ref.read(repositoryProvider).getAllCategories();
      for (final entry in selected) {
        final bill = entry.bill;
        final names = bill.type == BillType.transfer
            ? [bill.fromAccount!, bill.toAccount!]
            : [bill.account!];
        final valid = names.every((name) => accounts.any((account) =>
            account.ledgerId == session.ledgerId &&
            !account.hidden &&
            account.name.trim() == name.trim()));
        if (!valid ||
            (bill.type == BillType.transfer &&
                bill.fromAccount!.trim() == bill.toAccount!.trim())) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_label(
                '请填写账本中已有的不同资金账户', 'Choose existing, distinct accounts')),
          ));
          return;
        }
        if (bill.type != BillType.transfer &&
            !categories.any((category) =>
                category.kind == bill.type!.name &&
                category.name.trim() == bill.category!.trim())) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_label(
                '请选择已有的同类型分类', 'Choose an existing category of this type')),
          ));
          return;
        }
      }
      if (!mounted) return;
      setState(() => _saving = true);
      try {
        await _writes;
        final bookkeeper = ref.read(aiBookkeeperProvider);
        var savedCount = 0;
        for (final entry in selected) {
          final alreadySaved = await ref
              .read(repositoryProvider)
              .getTransactionBySyncId(entry.id);
          if (alreadySaved == null &&
              await _isPossibleDuplicate(entry.bill, session.ledgerId)) {
            if (!mounted) return;
            final proceed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(_label('疑似重复账单', 'Possible duplicate')),
                content: Text(_label('相同时间和金额附近已有一笔账单，仍要保存吗？',
                    'A transaction with a similar time and amount exists. Save anyway?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(_label('跳过', 'Skip'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(_label('仍然保存', 'Save anyway'))),
                ],
              ),
            );
            if (proceed != true) continue;
          }
          final bill = entry.bill;
          if (!mounted) return;
          final id = await bookkeeper.saveConfirmedImageBill(
            bill: bill,
            ledgerId: session.ledgerId,
            syncId: entry.id,
            billingTypes: [
              TagSeedService.billingTypeImage,
              TagSeedService.billingTypeAi
            ],
            l10n: AppLocalizations.of(context),
          );
          if (id == null) throw StateError('save-failed');
          savedCount++;
          if (savedCount == 1) {
            try {
              await BackgroundSyncRetry.schedule(session.ledgerId);
            } catch (_) {
              // The confirmed record is retained for the next foreground sync.
            }
          }
          final index =
              _session!.entries.indexWhere((item) => item.id == entry.id);
          _update(index, (item) => item.copyWith(saved: true));
          await _writes;
        }
        if (savedCount > 0) {
          await PostProcessor.run(ref,
              ledgerId: session.ledgerId, tags: true, attachments: false);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _label('已保存 $savedCount 笔', 'Saved $savedCount transactions')),
        ));
        if (_session!.entries
            .every((entry) => entry.saved || !entry.selected)) {
          Navigator.pop(context);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(_label('保存失败，草稿已保留', 'Save failed; the draft is kept')),
          ));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    } finally {
      _confirmPending = false;
    }
  }

  Future<void> _discard() async {
    final session = _session;
    await _writes;
    if (session != null) await _store.remove(session.id);
    await _deleteOwnedImage();
    if (mounted) Navigator.pop(context);
  }

  void _manual() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const TransactionEditorPage(initialKind: 'expense'),
    ));
  }

  Future<void> _pickNewImage() async {
    final selected = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (selected == null || !mounted) return;
    await _deleteOwnedImage();
    final cache = await getTemporaryDirectory();
    if (!mounted) return;
    setState(() {
      _image = File(selected.path);
      _ownsCurrentImage = p.isWithin(cache.path, p.normalize(selected.path));
      _error = null;
    });
    await _recognize();
  }

  Widget _field(int index, String key, String title, String? value,
          {TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: ValueKey('${_session!.entries[index].id}-$key'),
          initialValue: value ?? '',
          enabled: !_session!.entries[index].saved,
          keyboardType: keyboardType,
          decoration: InputDecoration(
              labelText: title, border: const OutlineInputBorder()),
          onChanged: (text) => _edit(index, key, text),
        ),
      );

  Widget _entry(int index, ImageDraftEntry entry) {
    final bill = entry.bill;
    return Card(
      key: ValueKey(entry.id),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
                '${_label('第', 'Transaction ')}${index + 1}${_label('笔', '')}'),
            subtitle: entry.saved ? Text(_label('已保存', 'Saved')) : null,
            value: entry.selected,
            onChanged: entry.saved
                ? null
                : (value) => _update(
                    index, (item) => item.copyWith(selected: value ?? false)),
          ),
          DropdownButtonFormField<String>(
            value: bill.type?.name,
            decoration: InputDecoration(labelText: _label('交易类型', 'Type')),
            items: [
              DropdownMenuItem(
                  value: 'expense', child: Text(_label('支出', 'Expense'))),
              DropdownMenuItem(
                  value: 'income', child: Text(_label('收入', 'Income'))),
              DropdownMenuItem(
                  value: 'transfer', child: Text(_label('转账', 'Transfer'))),
            ],
            onChanged: entry.saved
                ? null
                : (value) {
                    if (value != null) _edit(index, 'type', value);
                  },
          ),
          const SizedBox(height: 10),
          _field(index, 'amount', _label('金额', 'Amount'),
              bill.amount?.abs().toString(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true)),
          _field(
              index,
              'time',
              _label('日期时间（ISO 8601）', 'Date and time (ISO 8601)'),
              bill.time?.toIso8601String()),
          _field(index, 'category', _label('分类', 'Category'), bill.category),
          _field(index, 'merchant', _label('商家', 'Merchant'), bill.merchant),
          _field(index, 'item_description', _label('商品描述', 'Description'),
              bill.itemDescription),
          _field(index, 'payment_channel', _label('支付渠道', 'Payment channel'),
              bill.paymentChannel),
          _field(index, 'account', _label('资金账户', 'Account'), bill.account),
          if (bill.type == BillType.transfer) ...[
            _field(index, 'from_account', _label('转出账户', 'From account'),
                bill.fromAccount),
            _field(index, 'to_account', _label('转入账户', 'To account'),
                bill.toAccount),
          ],
          if (_missing(bill) != null)
            Text(_label('待补全：${_missing(bill)}', 'Missing: ${_missing(bill)}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: Text(_label('图片记账草稿', 'Image billing drafts'))),
      body: _recognizing
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_label('正在识别图片', 'Recognizing image')),
            ]))
          : session == null || session.entries.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error ?? _label('暂无草稿', 'No drafts yet')),
                    const SizedBox(height: 16),
                    if (_image != null)
                      FilledButton(
                          onPressed: _recognize,
                          child: Text(_label('重试识别', 'Retry recognition'))),
                    TextButton(
                        onPressed: _pickNewImage,
                        child: Text(_label('换张图片', 'Choose another image'))),
                    TextButton(
                        onPressed: _manual,
                        child: Text(_label('手动填写', 'Enter manually'))),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(_label('逐笔检查并修改，只有勾选后确认的账单才会入账。',
                        'Review each draft. Only selected and confirmed items will be saved.')),
                    const SizedBox(height: 16),
                    for (var i = 0; i < session.entries.length; i++)
                      _entry(i, session.entries[i]),
                  ],
                ),
      bottomNavigationBar: SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          TextButton(onPressed: _discard, child: Text(_label('丢弃', 'Discard'))),
          const Spacer(),
          if (session != null && session.entries.isNotEmpty)
            FilledButton(
                onPressed: _saving ? null : _confirm,
                child: Text(_label('确认入账', 'Confirm and save'))),
        ]),
      )),
    );
  }
}
