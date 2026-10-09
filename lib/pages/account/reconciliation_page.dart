import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/local/local_repository.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/reconciliation/reconciliation_engine.dart';
import '../../services/reconciliation/reconciliation_models.dart';
import '../../services/reconciliation/reconciliation_service.dart';
import '../../services/reconciliation/reconciliation_store.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../utils/beijing_time.dart';
import '../../widgets/ai/ai_privacy_consent_dialog.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'reconciliation_edit_dialog.dart';

class ReconciliationPage extends ConsumerStatefulWidget {
  const ReconciliationPage({super.key});
  @override
  ConsumerState<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends ConsumerState<ReconciliationPage> {
  ReconciliationSession? _session;
  ReconciliationSnapshot? _snapshot;
  List<ReconciliationSession> _history = [];
  final _inputErrors = <String, String>{};
  bool _busy = false;
  String _progress = '';
  ReconciliationStore get _store =>
      ReconciliationStore(ref.read(repositoryProvider) as LocalRepository);
  String _date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(beijingTime(value));

  @override
  void initState() {
    super.initState();
    unawaited(
      _run(() async {
        _history = await _store.list();
      }),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _save() async {
    final session = _session;
    if (session == null) return;
    try {
      await _store.save(session);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('对账保存失败：$e')));
      }
    }
  }

  Future<void> _new() => _run(() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final snapshot = await _store.snapshot();
    if (!snapshot.ledgers.any((l) => l.id == ledgerId && !l.isShared)) {
      throw StateError('请切换到个人账本后创建对账');
    }
    _session = ReconciliationSession(
      id: const Uuid().v4(),
      defaultLedgerId: ledgerId,
      defaultLedgerSyncId: snapshot.ledgers
          .singleWhere((l) => l.id == ledgerId)
          .syncId,
    );
    _snapshot = snapshot;
    _inputErrors.clear();
    await _store.save(_session!);
  });

  Future<void> _open(ReconciliationSession s) => _run(() async {
    _session = await _store.load(s.id);
    _snapshot = await _store.snapshot();
    _inputErrors.clear();
  });

  Future<void> _accounts() async {
    final s = _session!;
    final snapshot = await _store.snapshot();
    final available = snapshot.accounts
        .where((a) => isTradableType(a.type) && !isLiabilityType(a.type))
        .toList();
    final selected = s.accounts.map((a) => a.id).toSet();
    if (!mounted) return;
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('选择对账账户'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: available
                    .map(
                      (a) => CheckboxListTile(
                        title: Text(a.name),
                        subtitle: Text(a.currency),
                        value: selected.contains(a.id),
                        onChanged: (v) => change(() {
                          if (v == true) {
                            selected.add(a.id);
                          } else {
                            selected.remove(a.id);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      s.invalidate();
      for (final source
          in s.sources
              .where((src) => !result.contains(src['accountId']))
              .toList()) {
        await _store.removeImage(s, source['id']);
      }
      s.rows.removeWhere((r) => !result.contains(r.accountId));
      s.accounts = available
          .where((a) => result.contains(a.id))
          .map(
            (a) =>
                s.accounts.where((old) => old.id == a.id).firstOrNull ??
                ReconciliationAccount(
                  id: a.id,
                  name: a.name,
                  currency: a.currency,
                  syncId: a.syncId,
                  balanceAt: s.end,
                ),
          )
          .toList();
      _snapshot = snapshot;
      _inputErrors.clear();
      await _store.save(s);
    });
  }

  Future<void> _period() async {
    final s = _session!;
    final now = beijingNow();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: beijingTime(s.start),
        end: beijingTime(s.end),
      ),
    );
    if (range == null || !mounted) return;
    s.invalidate();
    s.start = beijingDate(
      range.start.year,
      range.start.month,
      range.start.day,
    ).toUtc();
    s.end =
        range.end.year == now.year &&
            range.end.month == now.month &&
            range.end.day == now.day
        ? now.toUtc()
        : beijingDate(
            range.end.year,
            range.end.month,
            range.end.day,
            23,
            59,
            59,
          ).toUtc();
    for (final a in s.accounts) {
      a.balanceAt = s.end;
    }
    _inputErrors.clear();
    setState(() {});
    await _save();
  }

  Future<void> _images(ReconciliationAccount a) => _run(() async {
    final images = await ImagePicker().pickMultiImage();
    for (final image in images) {
      await _store.addImage(_session!, a.id, File(image.path));
    }
  });

  Future<void> _row(
    ReconciliationAccount account, [
    StatementRow? existing,
  ]) async {
    final amount = TextEditingController(
      text: existing?.delta == null ? '' : moneyText(existing!.delta!),
    );
    final time = TextEditingController(
      text: existing?.time == null ? '' : _date(existing!.time!),
    );
    final balance = TextEditingController(
      text: existing?.balanceAfter == null
          ? ''
          : moneyText(existing!.balanceAfter!),
    );
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '手动补充外部流水' : '检查识别结果'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amount,
                    decoration: const InputDecoration(
                      labelText: '变动金额（支出负数，入账正数）',
                    ),
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
                  TextFormField(
                    controller: time,
                    decoration: const InputDecoration(
                      labelText: '北京时间（年-月-日 时:分:秒）',
                    ),
                    validator: (v) =>
                        evidenceTime(v) == null ? '请填写有效时间' : null,
                  ),
                  TextFormField(
                    controller: balance,
                    decoration: const InputDecoration(labelText: '交易后余额（可选）'),
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
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(labelText: '原始交易描述'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      _session!.invalidate();
      final row =
          existing ??
          StatementRow(
            id: 'manual:${const Uuid().v4()}',
            accountId: account.id,
            sourceIds: [],
          );
      row.delta = moneyCents(amount.text);
      row.time = evidenceTime(time.text);
      row.balanceAfter = moneyCents(balance.text);
      row.description = description.text;
      row.warnings.clear();
      if (existing == null) _session!.rows.add(row);
      setState(() {});
      await _save();
    }
    for (final controller in [amount, time, balance, description]) {
      controller.dispose();
    }
  }

  Future<void> _analyze() => _run(() async {
    if (_inputErrors.isNotEmpty) throw StateError(_inputErrors.values.first);
    if (!await ensureAiPrivacyConsent(context, ref)) return;
    if (!mounted) return;
    try {
      _snapshot = await ReconciliationService(_store).analyze(
        _session!,
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
      );
    } catch (_) {
      _session!.proposals = [];
      _session!.fingerprint = null;
      await _store.save(_session!);
      rethrow;
    }
  });

  Future<void> _apply() => _run(() async {
    final s = _session!;
    await _store.save(s);
    await _store.validate(s);
    if (!mounted) return;
    final count = s.proposals.where((p) => p['selected'] == true).length;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('应用已选修改'),
        content: Text('将应用 $count 组已选建议，并同步涉及的账本。请核对页面中的修改内容和余额预览。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认应用'),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    final ledgers = await _store.apply(s);
    await _refresh(ledgers);
  });

  Future<void> _undo() => _run(() async {
    final ledgers = await _store.undo(_session!);
    await _refresh(ledgers);
  });

  Future<void> _refresh(Set<int> ledgers) async {
    _snapshot = await _store.snapshot();
    if (!mounted) return;
    ref.invalidate(allAccountStatsProvider);
    ref.invalidate(allAccountsTotalStatsProvider);
    for (final id in ledgers) {
      await PostProcessor.run(ref, ledgerId: id, tags: true, attachments: true);
    }
  }

  Future<void> _edit(Json p, Json mutation) async {
    final edited = await editReconciliationMutation(
      context,
      mutation,
      _session!,
      _snapshot!,
    );
    if (edited == null || !mounted) return;
    mutation['after'] = edited;
    p['mutations'] = jsonObjects(
      p['mutations'],
    ).map((m) => m['id'] == mutation['id'] ? mutation : m).toList();
    final selections = {
      for (final proposal in _session!.proposals)
        proposal['id']: proposal['selected'],
    };
    for (final proposal in _session!.proposals) {
      proposal['selected'] = false;
    }
    p['selected'] = true;
    try {
      await _store.validate(_session!);
      p.remove('validationError');
    } catch (e) {
      p['validationError'] = '$e';
    }
    for (final proposal in _session!.proposals) {
      proposal['selected'] = selections[proposal['id']];
    }
    if (p['validationError'] != null) p['selected'] = false;
    setState(() {});
    await _save();
  }

  Widget _card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SectionCard(child: child),
  );

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          const PrimaryHeader(title: 'AI 对账', showBack: true, compact: true),
          if (_busy) const LinearProgressIndicator(),
          if (_progress.isNotEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text(_progress)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: s == null ? _historyView() : _sessionView(s),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _historyView() => [
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '核对多个账户的近期流水',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('添加完整期间截图，检查漏记、错账户、转账和退款。建议由你审核后应用，历史差额单独保留。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _new,
            icon: const Icon(Icons.add),
            label: const Text('新建对账'),
          ),
        ],
      ),
    ),
    ..._history.map(
      (s) => _card(
        ListTile(
          title: Text(
            s.accounts.isEmpty
                ? '未选择账户'
                : s.accounts.map((a) => a.name).join('、'),
          ),
          subtitle: Text(
            '${_date(s.start)} 至 ${_date(s.end)}\n${s.applied ? '已应用 · 可撤销' : '草稿／分析结果'}',
          ),
          isThreeLine: true,
          onTap: _busy ? null : () => _open(s),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy || s.applied
                ? null
                : () => _run(() async {
                    if (!await _confirmDelete()) return;
                    await _store.remove(s);
                    _history = await _store.list();
                  }),
          ),
        ),
      ),
    ),
  ];

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除对账草稿'),
          content: const Text('将删除本机草稿和截图副本，保留原图及记账记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;

  List<Widget> _sessionView(ReconciliationSession s) {
    final locked = _busy || s.applied;
    final snapshot = _snapshot;
    final reports = snapshot == null
        ? <AccountReconciliationReport>[]
        : reconciliationReports(
            s,
            snapshot.transactions,
            snapshot.initialBalances,
            proposals: s.applied ? [] : null,
          );
    return [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_date(s.start)} 至\n${_date(s.end)}'),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: locked ? null : _period,
                  child: const Text('选择期间'),
                ),
                TextButton(
                  onPressed: locked ? null : _accounts,
                  child: const Text('选择多个账户'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await _save();
                          _history = await _store.list();
                          _session = null;
                        }),
                  child: const Text('保存并返回列表'),
                ),
              ],
            ),
            const Text('截图和草稿仅保存在本机。分析时会发送截图及相关记账数据到已配置的 AI 服务。'),
          ],
        ),
      ),
      ...s.accounts.map((a) => _accountCard(s, a, locked)),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: locked || s.accounts.isEmpty ? null : _analyze,
              icon: const Icon(Icons.manage_search),
              label: Text(s.fingerprint == null ? '识别并分析' : '重新分析'),
            ),
            if (s.fingerprint != null &&
                snapshot?.fingerprint != s.fingerprint &&
                !s.applied)
              const Text('记账数据已变化，需要重新分析后应用。'),
            if (s.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(s.summary),
              ),
          ],
        ),
      ),
      ...reports.map(
        (r) => _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r.account.name} · ${r.account.currency}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '同期账面余额：${moneyText(r.bookBalance)}\n实际余额：${r.actualBalance == null ? '尚未提供' : moneyText(r.actualBalance!)}',
              ),
              if (!s.applied) Text('应用已选建议后：${moneyText(r.projectedBalance)}'),
              if (r.actualBalance != null)
                Text(
                  '剩余差额：${moneyText(r.actualBalance! - r.projectedBalance)}',
                ),
              if (r.periodDifference != null)
                Text('期间流水差额：${moneyText(r.periodDifference!)}'),
              if (r.openingDifference != null && r.openingDifference != 0)
                Text(
                  '期初已有差额：${moneyText(r.openingDifference!)}，需要补充更早证据，不生成余额调整。',
                ),
              ...r.warnings.map((w) => Text('· $w')),
            ],
          ),
        ),
      ),
      ...s.issues.map((issue) => _card(Text('待检查：$issue'))),
      ...s.proposals.map((p) => _proposalCard(s, p, locked)),
      if (s.proposals.isNotEmpty || s.applied)
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.applied) Text('已应用 ${s.audit!['appliedAt']}'),
              Wrap(
                spacing: 12,
                children: [
                  if (!s.applied)
                    FilledButton(
                      onPressed:
                          _busy ||
                              s.fingerprint == null ||
                              s.fingerprint != snapshot?.fingerprint ||
                              !s.proposals.any((p) => p['selected'] == true)
                          ? null
                          : _apply,
                      child: const Text('应用已选建议'),
                    ),
                  if (s.applied)
                    OutlinedButton(
                      onPressed: _busy ? null : _undo,
                      child: const Text('撤销本次修改'),
                    ),
                ],
              ),
              if (s.applied) const Text('若记录后来被编辑或同步更新，撤销会停止，避免覆盖后续修改。'),
            ],
          ),
        ),
      const SizedBox(height: 24),
    ];
  }

  Widget _accountCard(
    ReconciliationSession s,
    ReconciliationAccount a,
    bool locked,
  ) {
    final sources = s.sources.where((src) => src['accountId'] == a.id).toList();
    final rows = s.rows.where((r) => r.accountId == a.id).toList();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.name} · ${a.currency}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: locked ? null : () => _images(a),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('添加截图（${sources.length}）'),
              ),
              TextButton(
                onPressed: locked ? null : () => _row(a),
                child: const Text('手动补充流水'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: sources
                .map(
                  (src) => InputChip(
                    label: Text(
                      '截图 ${sources.indexOf(src) + 1}${src['recognized'] == true ? ' ✓' : ''}',
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(
                          child: Image.file(File(src['path'])),
                        ),
                      ),
                    ),
                    onDeleted: locked
                        ? null
                        : () => _run(() => _store.removeImage(s, src['id'])),
                  ),
                )
                .toList(),
          ),
          TextFormField(
            key: ValueKey('${s.id}:${a.id}:balance:${s.end}'),
            enabled: !locked,
            initialValue: a.actualBalance == null
                ? ''
                : moneyText(a.actualBalance!),
            decoration: const InputDecoration(
              labelText: '实际余额（可选；完整流水可使用最后交易余额）',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (value) {
              try {
                a.actualBalance = moneyCents(value);
                _inputErrors.remove('balance:${a.id}');
                s.invalidate();
              } catch (e) {
                _inputErrors['balance:${a.id}'] = '${a.name}：$e';
              }
              setState(() {});
              unawaited(_save());
            },
          ),
          TextFormField(
            key: ValueKey('${s.id}:${a.id}:time:${s.end}'),
            enabled: !locked,
            initialValue: _date(a.balanceAt),
            decoration: const InputDecoration(
              labelText: '余额对应的北京时间（年-月-日 时:分:秒）',
            ),
            onChanged: (value) {
              final parsed = evidenceTime(value);
              if (parsed == null ||
                  parsed.isBefore(s.start) ||
                  parsed.isAfter(s.end)) {
                _inputErrors['time:${a.id}'] = '${a.name}：余额时点需在对账期间内';
              } else {
                a.balanceAt = parsed;
                _inputErrors.remove('time:${a.id}');
                s.invalidate();
              }
              setState(() {});
              unawaited(_save());
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('已提供期间内全部余额变动'),
            subtitle: const Text('请包含收入、支出、充值、提现、转账和退款；账户时点之前的流水均需覆盖。'),
            value: a.complete,
            onChanged: locked
                ? null
                : (v) {
                    s.invalidate();
                    a.complete = v!;
                    setState(() {});
                    unawaited(_save());
                  },
          ),
          if (_inputErrors['balance:${a.id}'] != null)
            Text(_inputErrors['balance:${a.id}']!),
          if (_inputErrors['time:${a.id}'] != null)
            Text(_inputErrors['time:${a.id}']!),
          if (rows.isNotEmpty)
            ExpansionTile(
              title: Text('已识别 ${rows.length} 条流水 · 点击检查'),
              children: rows
                  .map(
                    (r) => ListTile(
                      title: Text(
                        '${r.delta == null ? '金额待确认' : moneyText(r.delta!)}  ${r.description}',
                      ),
                      subtitle: Text(
                        '${r.time == null ? '时间待确认' : _date(r.time!)}${r.balanceAfter == null ? '' : '\n交易后余额 ${moneyText(r.balanceAfter!)}'}${r.warnings.isEmpty ? '' : '\n${r.warnings.join('；')}'}',
                      ),
                      onTap: locked ? null : () => _row(a, r),
                      trailing: locked
                          ? null
                          : IconButton(
                              tooltip: '移除误识别流水',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                s.invalidate();
                                s.rows.remove(r);
                                setState(() {});
                                unawaited(_save());
                              },
                            ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  String _transactionText(Json t) {
    String name(Object? id) =>
        _snapshot?.accounts.where((a) => a.id == id).firstOrNull?.name ?? '未指定';
    final category =
        _snapshot?.categories
            .where((c) => c.id == t['categoryId'])
            .firstOrNull
            ?.name ??
        '未分类';
    final ledger =
        _snapshot?.ledgers
            .where((l) => l.id == t['ledgerId'])
            .firstOrNull
            ?.name ??
        '${t['ledgerId']}';
    final type = switch (t['type']) {
      'expense' => '支出／退款',
      'income' => '收入',
      'transfer' => '转账',
      _ => '${t['type']}',
    };
    return '$type ${moneyText(t['amountCents'])} · ${name(t['accountId'])}${t['type'] == 'transfer' ? ' → ${name(t['toAccountId'])}' : ''}\n'
        '${_date(evidenceTime(t['happenedAt'])!)} · $ledger · $category\n${t['merchant'] ?? ''} ${t['itemDescription'] ?? ''} ${t['note'] ?? ''}'
        '${t['refundOfSyncId'] != null || t['refundOfMutationId'] != null ? '\n关联原支出退款' : ''}';
  }

  Widget _proposalCard(ReconciliationSession s, Json p, bool locked) {
    final evidenceIds = List<String>.from(p['evidenceIds']);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p['title']?.toString() ?? '修改建议'),
            subtitle: Text(
              p['certainty'] == 'supported' ? '有证据支持 · 请核对' : '需要确认',
            ),
            value: p['selected'] == true,
            onChanged: locked || p['validationError'] != null
                ? null
                : (v) {
                    p['selected'] = v;
                    setState(() {});
                    unawaited(_save());
                  },
          ),
          Text(p['reason']?.toString() ?? ''),
          if (p['validationError'] != null)
            Text('暂不可应用：${p['validationError']}'),
          ...s.rows
              .where((r) => evidenceIds.contains(r.id))
              .map(
                (r) => Text(
                  '依据：${r.time == null ? '' : _date(r.time!)} ${r.delta == null ? '' : moneyText(r.delta!)} ${r.description}',
                ),
              ),
          ...jsonObjects(p['mutations']).map((m) {
            final before = _snapshot?.transactions
                .where((t) => t['id'] == m['transactionId'])
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    before == null
                        ? '新增记录'
                        : '原记录 #${before['id']}：\n${_transactionText(before)}',
                  ),
                  Text(
                    m['after'] == null
                        ? '建议删除此记录'
                        : '修改后：\n${_transactionText(jsonObject(m['after']))}',
                  ),
                  if (m['after'] != null)
                    TextButton(
                      onPressed: locked ? null : () => _edit(p, m),
                      child: const Text('编辑建议'),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
