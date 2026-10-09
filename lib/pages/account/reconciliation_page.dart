import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/local/local_repository.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/reconciliation/reconciliation_models.dart';
import '../../services/reconciliation/reconciliation_service.dart';
import '../../services/reconciliation/reconciliation_store.dart';
import '../../styles/tokens.dart';
import '../../utils/account_type_utils.dart';
import '../../widgets/ai/ai_privacy_consent_dialog.dart';
import '../../widgets/ui/ui.dart';
import 'reconciliation_edit_dialog.dart';
import 'reconciliation_input_view.dart';
import 'reconciliation_result_view.dart';
import 'reconciliation_setup_sheet.dart';
import 'reconciliation_statement_sheet.dart';
import 'reconciliation_ui.dart';

class ReconciliationPage extends ConsumerStatefulWidget {
  const ReconciliationPage({super.key});
  @override
  ConsumerState<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends ConsumerState<ReconciliationPage> {
  ReconciliationSession? _session;
  ReconciliationSnapshot? _snapshot;
  List<ReconciliationSession> _history = [];
  final _inputErrors = <int, String>{};
  final _scroll = ScrollController();
  Future<void> _pendingSave = Future.value();
  int _step = 0;
  bool _busy = false;
  String _progress = '';
  String? _error;
  String? _info;
  ReconciliationStore get _store =>
      ReconciliationStore(ref.read(repositoryProvider) as LocalRepository);

  @override
  void initState() {
    super.initState();
    unawaited(
      _run(() async {
        _history = await _store.list();
      }),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _pendingSave;
      await action();
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _save() {
    final s = _session;
    if (s == null) return Future.value();
    final copy = ReconciliationSession.fromJson(
      jsonObject(jsonDecode(jsonEncode(s.toJson()))),
    );
    return _pendingSave = _pendingSave
        .then((_) => _store.save(copy))
        .catchError((Object e) {
          if (mounted) setState(() => _error = '草稿保存失败：$e');
        });
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
    _info = null;
    await _save();
    if (mounted) _go(0);
  });

  Future<void> _open(ReconciliationSession session) => _run(() async {
    _session = await _store.load(session.id);
    _snapshot = await _store.snapshot();
    _inputErrors.clear();
    _info = null;
    if (mounted && _session != null) {
      _go(
        _session!.applied || _session!.fingerprint != null
            ? 2
            : _session!.accounts.isEmpty
            ? 0
            : 1,
      );
    }
  });

  Future<void> _historyBack() => _run(() async {
    await _save();
    _history = await _store.list();
    _session = null;
    _info = null;
    _inputErrors.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  });

  void _back() {
    if (_busy) return;
    if (_session == null) {
      Navigator.maybePop(context);
    } else if (_step > 0 && !_session!.applied) {
      _go(_step - 1);
    } else {
      unawaited(_historyBack());
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => ReconciliationTheme(
          child: Builder(
            builder: (context) => BeeAlertDialog(
              title: Text(title),
              content: Text(text),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;

  Future<void> _accounts() => _run(() async {
    final s = _session!;
    final snapshot = await _store.snapshot();
    final available = snapshot.accounts
        .where((a) => isTradableType(a.type) && !isLiabilityType(a.type))
        .toList();
    if (!mounted) return;
    final result = await selectReconciliationAccounts(
      context,
      available,
      s.accounts.map((a) => a.id).toSet(),
    );
    if (result == null || !mounted) return;
    if (result.length == s.accounts.length &&
        s.accounts.every((a) => result.contains(a.id))) {
      return;
    }
    final removedSources = s.sources
        .where((src) => !result.contains(src['accountId']))
        .toList();
    final removedRows = s.rows
        .where((r) => !result.contains(r.accountId))
        .toList();
    if ((removedSources.isNotEmpty || removedRows.isNotEmpty) &&
        !await _confirm(
          '移除账户资料',
          '取消选择的账户已有对账资料。移除后会删除本草稿中该账户的截图副本和流水，原图及账本记录不受影响。',
          '移除',
        )) {
      return;
    }
    s.invalidate();
    for (final source in removedSources) {
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
    _inputErrors.removeWhere((id, _) => !result.contains(id));
    await _save();
  });

  Future<void> _period() => _run(() async {
    final s = _session!;
    final range = await selectReconciliationPeriod(context, s.start, s.end);
    if (range == null ||
        !mounted ||
        (range.start == s.start && range.end == s.end)) {
      return;
    }
    s.invalidate();
    s.start = range.start;
    s.end = range.end;
    final cleared = <String>[];
    for (final a in s.accounts) {
      a.complete = false;
      if (a.balanceAt.isBefore(s.start) || a.balanceAt.isAfter(s.end)) {
        if (a.actualBalance != null) cleared.add(a.name);
        a.actualBalance = null;
        a.balanceAt = s.end;
        _inputErrors.remove(a.id);
      } else if (a.actualBalance == null) {
        a.balanceAt = s.end;
      }
    }
    _info = cleared.isEmpty
        ? '期间已更新，请重新确认各账户流水是否完整。'
        : '期间已更新。${cleared.join('、')}原余额时间不在新期间内，请重新填写余额。';
    await _save();
  });

  Future<void> _images(ReconciliationAccount account) => _run(() async {
    final images = await ImagePicker().pickMultiImage();
    for (final image in images) {
      await _store.addImage(_session!, account.id, File(image.path));
    }
    if (images.isNotEmpty) account.complete = false;
    await _save();
  });

  Future<void> _balanceTime(ReconciliationAccount account) => _run(() async {
    if (_inputErrors.containsKey(account.id)) {
      throw StateError('请先修正${account.name}的余额金额');
    }
    final s = _session!;
    final value = await pickReconciliationTime(
      context,
      title: '${account.name} · 余额时间',
      initial: account.balanceAt,
      first: s.start,
      last: s.end,
    );
    if (value == null || !mounted) return;
    s.invalidate();
    account.balanceAt = value;
    account.complete = false;
    await _save();
  });

  void _balance(ReconciliationAccount account, String value) {
    _session!.invalidate();
    try {
      account.actualBalance = moneyCents(value);
      _inputErrors.remove(account.id);
    } catch (_) {
      _inputErrors[account.id] = '请填写有效金额，最多两位小数';
    }
    setState(() {});
    unawaited(_save());
  }

  Future<void> _row(ReconciliationAccount account, [StatementRow? existing]) =>
      _run(() async {
        final row = await editReconciliationStatement(
          context,
          account,
          _session!.end,
          existing,
        );
        if (row == null || !mounted) return;
        final s = _session!;
        s.invalidate();
        final i = s.rows.indexWhere((r) => r.id == row.id);
        if (i < 0) {
          s.rows.add(row);
          account.complete = false;
        } else {
          s.rows[i] = row;
        }
        await _save();
      });

  Future<void> _removeRow(StatementRow row) => _run(() async {
    if (!await _confirm('移除对账流水', '这条流水将从对账资料中移除，账本记录不受影响。', '移除')) return;
    _session!.invalidate();
    _session!.rows.remove(row);
    _session!.accounts.singleWhere((a) => a.id == row.accountId).complete =
        false;
    await _save();
  });

  Future<void> _removeImage(ReconciliationAccount account, Json source) =>
      _run(() async {
        if (!await _confirm('移除截图', '移除本草稿中的截图及仅由它识别的流水，原图和账本记录不受影响。', '移除')) {
          return;
        }
        await _store.removeImage(_session!, source['id']);
        account.complete = false;
        await _save();
      });

  String? get _notReady {
    final s = _session!;
    if (_inputErrors.isNotEmpty) return '请修正实际余额的输入';
    final missing = s.accounts.where(
      (a) =>
          !s.sources.any((src) => src['accountId'] == a.id) &&
          !s.rows.any((r) => r.accountId == a.id) &&
          !(a.complete && a.actualBalance != null),
    );
    return missing.isEmpty
        ? null
        : '${missing.take(2).map((a) => a.name).join('、')}${missing.length > 2 ? '等 ${missing.length} 个账户' : ''}还没有流水资料；期间无交易时，请填写余额并勾选确认。';
  }

  Future<void> _analyze() => _run(() async {
    if (_notReady != null) throw StateError(_notReady!);
    if (!await ensureAiPrivacyConsent(context, ref) || !mounted) return;
    try {
      _snapshot = await ReconciliationService(_store).analyze(
        _session!,
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
      );
      if (mounted) {
        _info = null;
        _go(2);
      }
    } catch (_) {
      _session!.proposals = [];
      _session!.fingerprint = null;
      await _save();
      rethrow;
    }
  });

  Future<void> _apply() => _run(() async {
    final s = _session!;
    await _save();
    await _store.validate(s);
    if (!mounted) return;
    final proposals = s.proposals.where((p) => p['selected'] == true).toList();
    final mutations = proposals
        .expand((p) => jsonObjects(p['mutations']))
        .toList();
    final added = mutations.where((m) => m['transactionId'] == null).length;
    final deleted = mutations.where((m) => m['after'] == null).length;
    if (!await _confirm(
      '确认应用修改',
      '已选择 ${proposals.length} 组建议，共 ${mutations.length} 笔记录：\n新增 $added 笔，修改 ${mutations.length - added - deleted} 笔，删除 $deleted 笔。\n\n应用后会同步涉及的账本，可在本页撤销本次修改。',
      '确认应用',
    )) {
      return;
    }
    final ledgers = await _store.apply(s);
    await _refresh(ledgers);
    _info = '修改已应用。';
  });

  Future<void> _undo() => _run(() async {
    if (!await _confirm('撤销本次修改', '恢复本次修改前的记账记录，并同步涉及的账本。', '确认撤销')) return;
    final ledgers = await _store.undo(_session!);
    await _refresh(ledgers);
    _info = '本次修改已撤销，可以重新分析。';
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

  Future<void> _edit(Json p, Json mutation) => _run(() async {
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
    await _save();
  });

  @override
  Widget build(BuildContext context) => ReconciliationTheme(
    child: Builder(
      builder: (context) {
        final s = _session;
        return PopScope(
          canPop: s == null && !_busy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: Scaffold(
            backgroundColor: BeeTokens.scaffoldBackground(context),
            body: Column(
              children: [
                PrimaryHeader(
                  title: 'AI 对账',
                  showBack: true,
                  compact: true,
                  onBack: _back,
                  actions: s == null
                      ? null
                      : [
                          IconButton(
                            tooltip: '对账列表',
                            onPressed: _busy ? null : _historyBack,
                            icon: const Icon(Icons.history),
                          ),
                        ],
                ),
                if (s != null) _steps(context, s),
                if (_busy) const LinearProgressIndicator(),
                if (_progress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_progress),
                  ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      if (_error != null)
                        ReconciliationCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ReconciliationNotice(
                                  _error!,
                                  warning: true,
                                ),
                              ),
                              IconButton(
                                tooltip: '关闭提示',
                                onPressed: () => setState(() => _error = null),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      if (_info != null) ReconciliationNotice(_info!),
                      if (s == null)
                        ..._historyView(context)
                      else
                        ..._sessionView(s),
                    ],
                  ),
                ),
                if (s != null) _footer(context, s),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _steps(BuildContext context, ReconciliationSession s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: i == _step
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .1)
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                side: BorderSide(
                  color: i == _step
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed:
                  _busy ||
                      s.applied && i != 2 ||
                      i == 1 && s.accounts.isEmpty ||
                      i == 2 && s.fingerprint == null
                  ? null
                  : () => _go(i),
              child: Text('${i + 1} ${['设置', '流水', '审核'][i]}'),
            ),
          ),
        ],
      ],
    ),
  );

  List<Widget> _historyView(BuildContext context) => [
    const ReconciliationHeading(
      '核对近期资产流水',
      description: '把各账户的余额变动截图放在一起，找出漏记、错账和转账问题，审核后再修改。',
    ),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _new,
        icon: const Icon(Icons.add),
        label: const Text('开始新的对账'),
      ),
    ),
    const SizedBox(height: 24),
    ReconciliationHeading(
      '对账记录',
      description: _history.isEmpty ? '草稿会自动保存，可以随时回来继续。' : null,
    ),
    for (final s in _history)
      ReconciliationCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          title: Text(
            s.accounts.isEmpty
                ? '未完成设置'
                : s.accounts.map((a) => a.name).join('、'),
          ),
          subtitle: Text(
            '${reconciliationDate(s.start)} 至 ${reconciliationDate(s.end)}\n'
            '${s.applied
                ? '已应用 · 可撤销'
                : s.audit?['undone'] == true
                ? '已撤销'
                : s.fingerprint != null
                ? '已分析 · 待审核'
                : '草稿 · 可继续'}',
          ),
          isThreeLine: true,
          onTap: _busy ? null : () => _open(s),
          trailing: s.applied
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  tooltip: '删除草稿',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          if (!await _confirm(
                            '删除对账草稿',
                            '将删除本机草稿和截图副本，原图及账本记录不受影响。',
                            '删除',
                          )) {
                            return;
                          }
                          await _store.remove(s);
                          _history = await _store.list();
                        }),
                ),
        ),
      ),
  ];

  List<Widget> _sessionView(ReconciliationSession s) {
    final locked = _busy || s.applied;
    if (_step == 0) {
      return [
        ReconciliationSetupView(
          session: s,
          locked: locked,
          onAccounts: _accounts,
          onPeriod: _period,
        ),
      ];
    }
    if (_step == 2 && _snapshot != null) {
      return [
        ReconciliationResultView(
          session: s,
          snapshot: _snapshot!,
          locked: locked,
          onSelect: (p) {
            p['selected'] = p['selected'] != true;
            setState(() {});
            unawaited(_save());
          },
          onEdit: _edit,
          onStatements: () => _go(1),
        ),
      ];
    }
    return [
      ReconciliationHeading(
        '按账户添加流水资料',
        description:
            '${reconciliationDate(s.start)} 至 ${reconciliationDate(s.end)}\n'
            '截止 ${reconciliationDate(s.end, time: true)} · 北京时间',
      ),
      for (final a in s.accounts)
        ReconciliationAccountInput(
          session: s,
          account: a,
          locked: locked,
          balanceError: _inputErrors[a.id],
          onImages: () => _images(a),
          onTime: () => _balanceTime(a),
          onManual: () => _row(a),
          onBalance: (v) => _balance(a, v),
          onComplete: (v) {
            s.invalidate();
            a.complete = v;
            setState(() {});
            unawaited(_save());
          },
          onRemoveImage: (src) => _removeImage(a, src),
          onEditRow: (r) => _row(a, r),
          onRemoveRow: _removeRow,
        ),
      const ReconciliationNotice('分析会将截图和相关记账数据发送到你配置的 AI 服务。截图副本和草稿保存在本机。'),
    ];
  }

  Widget _footer(BuildContext context, ReconciliationSession s) {
    final count = s.proposals.where((p) => p['selected'] == true).length;
    final canApply =
        !_busy &&
        s.fingerprint != null &&
        s.fingerprint == _snapshot?.fingerprint &&
        count > 0;
    final hint = _step == 0
        ? (s.accounts.isEmpty ? '请选择至少一个资金账户' : '草稿自动保存在本机')
        : _step == 1
        ? (_notReady ?? '${s.accounts.length} 个账户已添加资料，可以开始分析')
        : s.applied
        ? '本次修改已应用，可撤销'
        : s.fingerprint != _snapshot?.fingerprint
        ? '记账数据已变化，请重新分析'
        : count == 0
        ? '请查看明细并勾选要应用的建议'
        : '已选择 $count 组修改建议';
    return Container(
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              if (_step == 0)
                FilledButton(
                  onPressed: _busy || s.accounts.isEmpty ? null : () => _go(1),
                  child: const Text('下一步：添加流水'),
                ),
              if (_step == 1)
                FilledButton.icon(
                  onPressed: _busy || _notReady != null ? null : _analyze,
                  icon: const Icon(Icons.manage_search),
                  label: Text(
                    _busy
                        ? '处理中…'
                        : s.fingerprint == null
                        ? '开始识别并分析'
                        : '重新分析',
                  ),
                ),
              if (_step == 2 && !s.applied)
                FilledButton(
                  onPressed: canApply ? _apply : null,
                  child: Text('应用已选建议（$count 组）'),
                ),
              if (_step == 2 && s.applied)
                OutlinedButton(
                  onPressed: _busy ? null : _undo,
                  child: const Text('撤销本次修改'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
