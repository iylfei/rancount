import 'dart:io';

import 'reconciliation_engine.dart';
import 'reconciliation_models.dart';
import 'reconciliation_store.dart';
import 'statement_recognizer.dart';

class ReconciliationService {
  final ReconciliationStore store;
  final StatementRecognizer recognizer;
  final ReconciliationEngine engine;
  const ReconciliationService(
    this.store, {
    this.recognizer = const StatementRecognizer(),
    this.engine = const ReconciliationEngine(),
  });

  Future<ReconciliationSnapshot> analyze(
    ReconciliationSession s, {
    void Function(String)? onProgress,
  }) async {
    if (s.applied) throw StateError('请先撤销修改或新建对账');
    if (s.accounts.isEmpty || !s.start.isBefore(s.end)) {
      throw StateError('请选择账户和有效期间');
    }
    store.assertIdentity(s, await store.snapshot());
    s.invalidate();
    await store.save(s);
    for (var i = 0; i < s.sources.length; i++) {
      final source = s.sources[i];
      final account = s.accounts.singleWhere(
        (a) => a.id == source['accountId'],
      );
      final needsCardCheck =
          (account.cardLast4 != null &&
              source['cardRecognitionVersion'] !=
                  StatementRecognizer.cardRecognitionVersion) ||
          (source['cardRecognitionVersion'] ==
                  StatementRecognizer.cardRecognitionVersion &&
              source['accountCardLast4'] != account.cardLast4);
      if (source['recognized'] == true && !needsCardCheck) continue;
      onProgress?.call('识别截图 ${i + 1} / ${s.sources.length}');
      final rows = await recognizer.recognize(
        File(source['path']),
        source,
        account,
      );
      // Replace this source only after successful recognition. Keep manual
      // additions and evidence contributed by other screenshots.
      s.rows.removeWhere((r) {
        if (!r.sourceIds.contains(source['id'])) return false;
        r.sourceIds.remove(source['id']);
        return r.sourceIds.isEmpty && !r.id.startsWith('manual:');
      });
      s.rows.addAll(rows);
      s.rows = mergeStatementRows(s.rows);
      source['recognized'] = true;
      await store.save(s);
    }
    final snapshot = await store.snapshot();
    store.assertIdentity(s, snapshot);
    // Legacy OCR padded minute-only timestamps with :00. Its original
    // sources have no precision metadata, so preserve known payment seconds.
    for (final row in s.rows) {
      if (row.time == null ||
          row.timePrecision != 'second' ||
          row.sourceIds.isEmpty) {
        continue;
      }
      final legacy = row.sourceIds.every(
        (id) => s.sources.any(
          (source) =>
              source['id'] == id && source['cardRecognitionVersion'] == null,
        ),
      );
      if (legacy && row.time!.second == 0) row.timePrecision = 'minute';
    }
    s.refreshEvidenceCompleteness();
    await engine.analyze(
      s,
      snapshot.transactions,
      snapshot.initialBalances,
      snapshot.categories
          .map((c) => {'id': c.id, 'name': c.name, 'kind': c.kind})
          .toList(),
      snapshot.ledgers
          .where((l) => !l.isShared)
          .map((l) => {'id': l.id, 'name': l.name, 'currency': l.currency})
          .toList(),
      snapshot.accounts
          .map(
            (a) => {
              'id': a.id,
              'name': a.name,
              'currency': a.currency,
              'type': a.type,
            },
          )
          .toList(),
      onProgress: onProgress,
    );
    s.fingerprint = snapshot.fingerprint;
    s.analysisVersion = reconciliationAnalysisVersion;
    for (final source in s.sources) {
      s.issues.addAll(
        List<String>.from(
          source['warnings'] ?? [],
        ).map((w) => '截图 ${s.sources.indexOf(source) + 1}：$w'),
      );
    }
    // Validate each dependency group before presenting it as executable.
    for (final proposal in s.proposals) {
      proposal['selected'] = true;
      try {
        await store.validate(s, snapshot: snapshot);
        proposal.remove('validationError');
      } catch (e) {
        proposal['validationError'] = e.toString();
      } finally {
        proposal['selected'] = false;
      }
    }
    await store.save(s);
    return snapshot;
  }
}
