import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as d;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../utils/account_type_utils.dart';
import 'reconciliation_models.dart';

Json reconciliationTransaction(Transaction t) => {
  'id': t.id,
  'syncId': t.syncId,
  'ledgerId': t.ledgerId,
  'type': t.type,
  'amountCents': storedCents(t.amount),
  'accountId': t.accountId,
  'toAccountId': t.toAccountId,
  'categoryId': t.categoryId,
  'happenedAt': t.happenedAt.toUtc().toIso8601String(),
  'note': t.note,
  'merchant': t.merchant,
  'itemDescription': t.itemDescription,
  'paymentChannel': t.paymentChannel,
  'refundOfSyncId': t.refundOfSyncId,
  'excludeFromStats': t.excludeFromStats,
  'excludeFromBudget': t.excludeFromBudget,
  'currencyCode': t.currencyCode,
};

class ReconciliationSnapshot {
  final List<Transaction> records;
  final List<Account> accounts;
  final List<Ledger> ledgers;
  final List<Category> categories;
  final String fingerprint;
  ReconciliationSnapshot(
    this.records,
    this.accounts,
    this.ledgers,
    this.categories,
    this.fingerprint,
  );
  List<Json> get transactions =>
      records.map(reconciliationTransaction).toList();
  Map<int, int> get initialBalances => {
    for (final a in accounts) a.id: storedCents(a.initialBalance),
  };
}

class ReconciliationStore {
  final LocalRepository repository;
  final Future<Directory> Function()? evidenceDirectory;
  BeeDatabase get db => repository.db;
  ReconciliationStore(this.repository, {this.evidenceDirectory});

  Future<void> save(ReconciliationSession s) => db.customStatement(
    'INSERT INTO reconciliation_sessions (id,payload,updated_at) VALUES (?,?,?) '
    'ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at',
    [s.id, jsonEncode(s.toJson()), DateTime.now().millisecondsSinceEpoch],
  );

  Future<ReconciliationSession?> load(String id) async {
    final row = await db
        .customSelect(
          'SELECT payload FROM reconciliation_sessions WHERE id=?',
          variables: [d.Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : ReconciliationSession.fromJson(
            jsonObject(jsonDecode(row.read<String>('payload'))),
          );
  }

  Future<List<ReconciliationSession>> list() async =>
      (await db
              .customSelect(
                'SELECT payload FROM reconciliation_sessions ORDER BY updated_at DESC',
              )
              .get())
          .map(
            (r) => ReconciliationSession.fromJson(
              jsonObject(jsonDecode(r.read<String>('payload'))),
            ),
          )
          .toList();

  Future<Directory> _directory(String id) async {
    final root = evidenceDirectory == null
        ? await getApplicationSupportDirectory()
        : await evidenceDirectory!();
    return Directory(p.join(root.path, 'reconciliation', id));
  }

  Future<void> addImage(
    ReconciliationSession s,
    int accountId,
    File image,
  ) async {
    final bytes = await image.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    if (s.sources.any(
      (src) => src['accountId'] == accountId && src['hash'] == hash,
    )) {
      return;
    }
    s.invalidate();
    final directory = await _directory(s.id);
    await directory.create(recursive: true);
    final id = const Uuid().v4();
    final extension = p.extension(image.path).toLowerCase();
    if (!['.png', '.jpg', '.jpeg', '.webp', '.heic'].contains(extension)) {
      throw StateError('请选择支持的图片文件');
    }
    final file = File(p.join(directory.path, '$id$extension'));
    await file.writeAsBytes(bytes, flush: true);
    s.sources.add({
      'id': id,
      'accountId': accountId,
      'hash': hash,
      'path': file.path,
      'recognized': false,
      'warnings': <String>[],
    });
    await save(s);
  }

  Future<void> removeImage(ReconciliationSession s, String id) async {
    s.invalidate();
    final source = s.sources.singleWhere((src) => src['id'] == id);
    s.sources.remove(source);
    s.rows.removeWhere((r) {
      r.sourceIds.remove(id);
      return r.sourceIds.isEmpty;
    });
    await save(s);
    final file = File(source['path']);
    if (await file.exists()) await file.delete();
  }

  Future<void> remove(ReconciliationSession s) async {
    final saved = await load(s.id);
    if (saved?.applied == true) throw StateError('请先撤销已应用修改，再删除对账');
    await db.customStatement('DELETE FROM reconciliation_sessions WHERE id=?', [
      s.id,
    ]);
    final directory = await _directory(s.id);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<ReconciliationSnapshot> snapshot() async => db.transaction(() async {
    final ledgers = await repository.getAllLedgers();
    final personalIds = ledgers
        .where((l) => !l.isShared)
        .map((l) => l.id)
        .toList();
    final records =
        await (db.select(db.transactions)
              ..where((t) => t.ledgerId.isIn(personalIds))
              ..orderBy([(t) => d.OrderingTerm.asc(t.id)]))
            .get();
    final accounts = await (db.select(
      db.accounts,
    )..orderBy([(a) => d.OrderingTerm.asc(a.id)])).get();
    final categories = await (db.select(
      db.categories,
    )..orderBy([(c) => d.OrderingTerm.asc(c.id)])).get();
    final links = await _links(records.map((t) => t.id).toList());
    final data = [
      records.map((t) => t.toJson()).toList(),
      accounts.map((a) => a.toJson()).toList(),
      categories.map((c) => c.toJson()).toList(),
      (ledgers.toList()..sort((a, b) => a.id.compareTo(b.id)))
          .map((l) => l.toJson())
          .toList(),
      links,
    ];
    return ReconciliationSnapshot(
      records,
      accounts,
      ledgers,
      categories,
      sha256.convert(utf8.encode(jsonEncode(data))).toString(),
    );
  });

  Future<Json> _links(List<int> ids) async {
    final tags =
        await (db.select(db.transactionTags)
              ..where((t) => t.transactionId.isIn(ids))
              ..orderBy([
                (t) => d.OrderingTerm.asc(t.transactionId),
                (t) => d.OrderingTerm.asc(t.tagId),
              ]))
            .get();
    final attachments =
        await (db.select(db.transactionAttachments)
              ..where((t) => t.transactionId.isIn(ids))
              ..orderBy([(t) => d.OrderingTerm.asc(t.id)]))
            .get();
    return {
      'tags': tags.map((t) => t.toJson()).toList(),
      'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }

  void assertIdentity(
    ReconciliationSession s,
    ReconciliationSnapshot snapshot,
  ) {
    final ledger = snapshot.ledgers
        .where((l) => l.id == s.defaultLedgerId && !l.isShared)
        .firstOrNull;
    if (ledger == null ||
        (s.defaultLedgerSyncId != null &&
            ledger.syncId != s.defaultLedgerSyncId)) {
      throw StateError('账本已删除或更换，请新建对账');
    }
    for (final account in s.accounts) {
      final current = snapshot.accounts
          .where((a) => a.id == account.id)
          .firstOrNull;
      if (current == null ||
          current.currency != account.currency ||
          !isTradableType(current.type) ||
          isLiabilityType(current.type) != account.isLiability ||
          (account.syncId != null
              ? current.syncId != account.syncId
              : current.name != account.name)) {
        throw StateError('账户已删除或更换，请新建对账并重新指定截图所属账户');
      }
    }
  }

  Future<void> validate(
    ReconciliationSession s, {
    ReconciliationSnapshot? snapshot,
  }) async {
    await _prepare(s, snapshot ?? await this.snapshot());
  }

  Future<List<(Json, Transaction?, Transaction?)>> _prepare(
    ReconciliationSession s,
    ReconciliationSnapshot snap,
  ) async {
    assertIdentity(s, snap);
    final mutations = s.proposals
        .where((p) => p['selected'] == true)
        .expand((p) => jsonObjects(p['mutations']))
        .toList();
    final working = {for (final t in snap.records) t.id: t};
    final accounts = {for (final a in snap.accounts) a.id: a};
    final ledgers = {
      for (final l in snap.ledgers.where((l) => !l.isShared)) l.id: l,
    };
    final categories = {for (final c in snap.categories) c.id: c};
    final selected = s.accounts.map((a) => a.id).toSet();
    final touched = <int>{};
    final ids = mutations.map((m) => m['id'] as String).toSet();
    if (ids.length != mutations.length) throw StateError('修改操作标识重复');
    final result = <(Json, Transaction?, Transaction?)>[];
    var syntheticId = -1;
    for (final m in mutations) {
      final beforeId = m['transactionId'] as int?;
      final before = beforeId == null ? null : working[beforeId];
      if (beforeId != null && (before == null || !touched.add(beforeId))) {
        throw StateError('原记账记录不存在或在计划中重复修改');
      }
      if (before != null &&
          (before.happenedAt.isBefore(s.start) ||
              before.happenedAt.isAfter(s.end))) {
        throw StateError('只能修改本次对账期间内的记录');
      }
      for (final id in [
        before?.accountId,
        before?.toAccountId,
      ].whereType<int>()) {
        if (!selected.contains(id)) throw StateError('建议涉及未选择的账户，请加入对账后重新分析');
      }
      Transaction? after;
      if (m['after'] != null) {
        final a = jsonObject(m['after']);
        final type = a['type'];
        final amount = a['amountCents'];
        final time = evidenceTime(a['happenedAt']);
        final account = accounts[a['accountId']];
        final toAccount = type == 'transfer'
            ? accounts[a['toAccountId']]
            : null;
        final ledger = ledgers[a['ledgerId']];
        final category = a['categoryId'] == null
            ? null
            : categories[a['categoryId']];
        if (!['expense', 'income', 'transfer'].contains(type) ||
            amount is! int ||
            amount == 0 ||
            amount.abs() > 9007199254740991 ||
            time == null ||
            time.isBefore(s.start) ||
            time.isAfter(s.end) ||
            account == null ||
            !isTradableType(account.type) ||
            !selected.contains(account.id) ||
            ledger == null ||
            (before != null && before.ledgerId != ledger.id)) {
          throw StateError('建议包含无效金额、时间、账本或账户，请编辑后再应用');
        }
        if (a['categoryId'] != null &&
            (category == null || category.kind != type)) {
          throw StateError('分类与交易类型不一致');
        }
        if (type != 'expense' && amount < 0) throw StateError('收入和转账金额必须为正数');
        if (type == 'transfer' &&
            (toAccount == null ||
                toAccount.id == account.id ||
                !selected.contains(toAccount.id) ||
                !isTradableType(toAccount.type) ||
                toAccount.currency != account.currency)) {
          throw StateError('转账需要两个不同的、已选择的同币种日常账户');
        }
        String? refund = a['refundOfSyncId'];
        if (a['refundOfMutationId'] != null) {
          if (!ids.contains(a['refundOfMutationId'])) {
            throw StateError('退款原支出必须在同次修改中确认');
          }
          final originalMutation = mutations.singleWhere(
            (m) => m['id'] == a['refundOfMutationId'],
          );
          final originalId = originalMutation['transactionId'];
          refund = originalId == null
              ? const Uuid().v5(Namespace.url.value, a['refundOfMutationId'])
              : working[originalId]?.syncId;
        }
        if (before?.refundOfSyncId != null &&
            refund != before!.refundOfSyncId) {
          throw StateError('已关联退款不能移除或更换原支出');
        }
        if (amount < 0 && refund == null && before?.amount.isNegative != true) {
          throw StateError('新增退款必须关联原支出');
        }
        final currency = account.currency;
        double native = amount / 100;
        if (before != null &&
            (before.currencyCode ?? accounts[before.accountId]?.currency) ==
                currency &&
            before.amount != 0) {
          native *= (before.nativeAmount ?? before.amount) / before.amount;
        } else if (currency != ledger.currency) {
          final overrides = await repository.getOverrides(ledger.currency);
          final rates = await repository.getLatestAutoRates(ledger.currency);
          final rate =
              overrides
                  .where((r) => r.quoteCurrency == currency)
                  .firstOrNull
                  ?.rate ??
              rates.where((r) => r.quoteCurrency == currency).firstOrNull?.rate;
          final parsed = double.tryParse(rate ?? '');
          if (parsed == null || !parsed.isFinite || parsed <= 0) {
            throw StateError('缺少 $currency 到 ${ledger.currency} 的有效汇率');
          }
          native *= parsed;
        }
        after = Transaction(
          id: before?.id ?? syntheticId--,
          ledgerId: ledger.id,
          type: type,
          amount: amount / 100,
          categoryId: type == 'transfer' ? null : category?.id,
          accountId: account.id,
          toAccountId: toAccount?.id,
          happenedAt: time,
          note: a['note'],
          merchant: a['merchant'],
          itemDescription: a['itemDescription'],
          paymentChannel: a['paymentChannel'],
          refundOfSyncId: refund,
          syncId:
              before?.syncId ?? const Uuid().v5(Namespace.url.value, m['id']),
          recurringId: before?.recurringId,
          createdByUserId: before?.createdByUserId,
          lastEditedByUserId: before?.lastEditedByUserId,
          excludeFromStats: before?.excludeFromStats ?? false,
          excludeFromBudget: before?.excludeFromBudget ?? false,
          currencyCode: currency,
          nativeAmount: native,
        );
        working[after.id] = after;
      } else {
        if (before == null) throw StateError('删除操作缺少原记录');
        if (s.accounts.any((a) => !a.complete)) {
          throw StateError('流水资料仍有未识别或待确认内容，暂不能应用删除建议');
        }
        working.remove(before.id);
      }
      result.add((m, before, after));
    }
    _validateRefunds(working.values);
    return result;
  }

  void _validateRefunds(Iterable<Transaction> records) {
    final bySyncId = {
      for (final t in records)
        if (t.syncId != null) t.syncId!: t,
    };
    final totals = <String, int>{};
    for (final t in records.where((t) => t.refundOfSyncId != null)) {
      final original = bySyncId[t.refundOfSyncId];
      if (original == null ||
          original.type != 'expense' ||
          original.amount <= 0 ||
          t.type != 'expense' ||
          t.amount >= 0 ||
          t.categoryId != original.categoryId ||
          t.currencyCode != original.currencyCode ||
          t.ledgerId != original.ledgerId) {
        throw StateError('退款必须关联同账本、同币种和同分类的原支出');
      }
      totals.update(
        original.syncId!,
        (v) => v - storedCents(t.amount),
        ifAbsent: () => -storedCents(t.amount),
      );
      if (totals[original.syncId]! > storedCents(original.amount)) {
        throw StateError('退款总额超过原支出');
      }
    }
  }

  Future<Set<int>> apply(ReconciliationSession s) async {
    Json? committedAudit;
    final ledgers = await db.transaction(() async {
      final persisted = await load(s.id);
      if (persisted?.applied == true) {
        committedAudit = persisted!.audit;
        return (persisted.audit!['ledgerIds'] as List).cast<int>().toSet();
      }
      if (persisted == null ||
          persisted.fingerprint == null ||
          jsonEncode(persisted.proposals) != jsonEncode(s.proposals)) {
        throw StateError('修改计划已变化，请重新保存并核对');
      }
      final snap = await snapshot();
      if (snap.fingerprint != s.fingerprint) {
        throw StateError('记账或同步数据已变化，请重新分析');
      }
      final prepared = await _prepare(s, snap);
      if (prepared.isEmpty) throw StateError('请先选择需要应用的建议');
      final affected = <int>{};
      final changes = <Json>[];
      for (final (_, before, proposed) in prepared) {
        var after = proposed;
        final links = before == null
            ? {'tags': [], 'attachments': []}
            : await _links([before.id]);
        if (after != null) {
          if (before == null) {
            final id = await db
                .into(db.transactions)
                .insert(
                  after.toCompanion(true).copyWith(id: const d.Value.absent()),
                );
            after = after.copyWith(id: id);
          } else {
            await (db.update(db.transactions)
                  ..where((t) => t.id.equals(before.id)))
                .write(after.toCompanion(false));
          }
          await _track(after, before == null ? 'create' : 'update');
          affected.add(after.ledgerId);
        } else {
          await _delete(before!);
          affected.add(before.ledgerId);
        }
        changes.add({
          'before': before?.toJson(),
          'after': after?.toJson(),
          'links': links,
          'afterLinks': after == null
              ? {'tags': [], 'attachments': []}
              : await _links([after.id]),
        });
      }
      final audit = {
        'id': const Uuid().v4(),
        'appliedAt': DateTime.now().toUtc().toIso8601String(),
        'changes': changes,
        'ledgerIds': affected.toList(),
        'undone': false,
      };
      await db.customStatement(
        'INSERT INTO reconciliation_audits (id,session_id,payload,created_at) VALUES (?,?,?,?)',
        [
          audit['id'],
          s.id,
          jsonEncode(audit),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      final updated = ReconciliationSession.fromJson(s.toJson())..audit = audit;
      await save(updated);
      committedAudit = audit;
      return affected;
    });
    s.audit = committedAudit;
    return ledgers;
  }

  Future<void> _track(Transaction t, String action) async {
    if (t.syncId == null) throw StateError('记录缺少同步标识，无法安全修改');
    await repository.changeTracker?.recordLedgerChange(
      entityType: 'transaction',
      entityId: t.id,
      entitySyncId: t.syncId!,
      ledgerId: t.ledgerId,
      action: action,
    );
  }

  Future<void> _delete(Transaction t) async {
    // Keep physical attachment files for undo. Only relations are removed.
    await (db.delete(
      db.transactionTags,
    )..where((r) => r.transactionId.equals(t.id))).go();
    await (db.delete(
      db.transactionAttachments,
    )..where((r) => r.transactionId.equals(t.id))).go();
    await (db.delete(db.transactions)..where((r) => r.id.equals(t.id))).go();
    await _track(t, 'delete');
  }

  Future<Set<int>> undo(ReconciliationSession s) async {
    Json? committedAudit;
    final result = await db.transaction(() async {
      final persisted = await load(s.id);
      if (persisted == null || !persisted.applied) throw StateError('没有可撤销的修改');
      final audit = jsonObject(persisted.audit);
      final changes = jsonObjects(audit['changes']);
      // Check all rows before writing anything, including edits to their links.
      for (final change in changes) {
        final before = change['before'] == null
            ? null
            : Transaction.fromJson(jsonObject(change['before']));
        final after = change['after'] == null
            ? null
            : Transaction.fromJson(jsonObject(change['after']));
        final id = after?.id ?? before!.id;
        final current = await repository.getTransactionById(id);
        if (jsonEncode(current?.toJson()) != jsonEncode(after?.toJson()) ||
            jsonEncode(await _links([id])) !=
                jsonEncode(change['afterLinks'])) {
          throw StateError('记录已被再次修改或同步更新，不能覆盖撤销');
        }
      }
      final all = (await db.select(db.transactions).get())
          .map((t) => t.toJson())
          .toList();
      for (final change in changes) {
        final row = change['after'] ?? change['before'];
        final id = jsonObject(row)['id'];
        all.removeWhere((t) => t['id'] == id);
        if (change['before'] != null) all.add(jsonObject(change['before']));
      }
      _validateRefunds(all.map(Transaction.fromJson));
      for (final change in changes.reversed) {
        final before = change['before'] == null
            ? null
            : Transaction.fromJson(jsonObject(change['before']));
        final after = change['after'] == null
            ? null
            : Transaction.fromJson(jsonObject(change['after']));
        if (before == null) {
          await _delete(after!);
        } else {
          await db
              .into(db.transactions)
              .insertOnConflictUpdate(before.toCompanion(false));
          if (after == null) {
            final links = jsonObject(change['links']);
            for (final tag in jsonObjects(links['tags'])) {
              await db
                  .into(db.transactionTags)
                  .insert(TransactionTag.fromJson(tag).toCompanion(false));
            }
            for (final attachment in jsonObjects(links['attachments'])) {
              await db
                  .into(db.transactionAttachments)
                  .insert(
                    TransactionAttachment.fromJson(
                      attachment,
                    ).toCompanion(false),
                  );
            }
          }
          await _track(before, after == null ? 'create' : 'update');
        }
      }
      audit['undone'] = true;
      audit['undoneAt'] = DateTime.now().toUtc().toIso8601String();
      await db.customStatement(
        'UPDATE reconciliation_audits SET payload=? WHERE id=?',
        [jsonEncode(audit), audit['id']],
      );
      persisted.audit = audit;
      persisted.fingerprint = null;
      await save(persisted);
      committedAudit = audit;
      return (audit['ledgerIds'] as List).cast<int>().toSet();
    });
    s.audit = committedAudit;
    s.fingerprint = null;
    return result;
  }
}
