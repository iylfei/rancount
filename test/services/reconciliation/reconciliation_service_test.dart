import 'dart:convert';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/reconciliation/reconciliation_engine.dart';
import 'package:beecount/services/reconciliation/reconciliation_models.dart';
import 'package:beecount/services/reconciliation/reconciliation_service.dart';
import 'package:beecount/services/reconciliation/reconciliation_store.dart';
import 'package:beecount/services/reconciliation/statement_recognizer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase database;
  late ReconciliationStore store;
  late ReconciliationSession session;
  final time = DateTime.utc(2026, 10, 5);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = BeeDatabase.forTesting(NativeDatabase.memory());
    final repository = LocalRepository(database);
    store = ReconciliationStore(repository);
    final ledger = await repository.createLedger(name: '日常');
    final account = await repository.createAccount(
      ledgerId: ledger,
      name: '钱包',
      type: 'alipay',
      initialBalance: 100,
    );
    session = ReconciliationSession(
      id: 'continue',
      defaultLedgerId: ledger,
      start: DateTime.utc(2026, 10, 1),
      end: DateTime.utc(2026, 10, 9),
      accounts: [
        ReconciliationAccount(
          id: account,
          name: '钱包',
          currency: 'CNY',
          balanceAt: time,
        ),
      ],
      sources: [
        {
          'id': 'image',
          'accountId': account,
          'path': 'cached.png',
          'recognized': true,
        },
      ],
      rows: [
        StatementRow(
          id: 'image:0',
          accountId: account,
          sourceIds: ['image'],
          time: time,
          delta: -1000,
          balanceAfter: 9000,
        ),
      ],
    );
  });
  tearDown(() => database.close());

  StatementRecognizer cachedRecognizer() => StatementRecognizer(
    vision: (_, __) async =>
        throw StateError('Cached screenshot must not be recognized again'),
  );

  test(
    'recognized draft continues analysis and saves reviewable results without ledger writes',
    () async {
      var calls = 0;
      final snapshot = await ReconciliationService(
        store,
        recognizer: cachedRecognizer(),
        engine: ReconciliationEngine(
          chat: (prompt) async {
            calls++;
            expect(prompt, contains('image:0'));
            return jsonEncode({
              'summary': '钱包漏记支出 10 元',
              'issues': [],
              'proposals': [
                {
                  'title': '补记支出',
                  'evidenceIds': ['image:0'],
                  'mutations': [
                    {
                      'id': 'add',
                      'after': {
                        'ledgerId': session.defaultLedgerId,
                        'type': 'expense',
                        'amountCents': 1000,
                        'accountId': session.accounts.single.id,
                        'happenedAt': time.toIso8601String(),
                      },
                    },
                  ],
                },
              ],
            });
          },
        ),
      ).analyze(session);
      final saved = (await store.load(session.id))!;
      expect(calls, 1);
      expect(saved.fingerprint, snapshot.fingerprint);
      expect(saved.analysisVersion, reconciliationAnalysisVersion);
      expect(saved.proposals, hasLength(1));
      expect(saved.proposals.single['selected'], isFalse);
      expect(saved.proposals.single['validationError'], isNull);
      expect(snapshot.transactions, isEmpty);
      expect(saved.rows, hasLength(1));
    },
  );

  test(
    'failed analysis leaves recognized draft resumable and retry skips OCR',
    () async {
      await expectLater(
        ReconciliationService(
          store,
          recognizer: cachedRecognizer(),
          engine: ReconciliationEngine(
            chat: (_) async => throw StateError('服务暂时不可用'),
          ),
        ).analyze(session),
        throwsStateError,
      );
      expect(session.fingerprint, isNull);
      final saved = (await store.load(session.id))!;
      expect(saved.fingerprint, isNull);
      expect(saved.analysisVersion, 0);
      expect(saved.sources.single['recognized'], isTrue);
      expect(saved.rows.single.delta, -1000);
      final snapshot = await ReconciliationService(
        store,
        recognizer: cachedRecognizer(),
        engine: ReconciliationEngine(
          chat: (_) async => '{"summary":"重新分析完成","issues":[],"proposals":[]}',
        ),
      ).analyze(saved);
      expect(saved.fingerprint, snapshot.fingerprint);
      expect(saved.summary, contains('重新分析完成'));
      expect(saved.sources.single['recognized'], isTrue);
      expect(saved.rows, hasLength(1));
      expect((await store.load(saved.id))!.fingerprint, snapshot.fingerprint);
    },
  );

  test(
    'card mapping refreshes legacy OCR once and replaces only its own cached rows',
    () async {
      session.accounts.single.cardLast4 = '9053';
      session.rows.add(
        StatementRow(
          id: 'manual:keep',
          accountId: session.accounts.single.id,
          sourceIds: [],
          time: time,
          delta: -200,
        ),
      );
      var recognitions = 0;
      final recognizer = StatementRecognizer(
        vision: (_, prompt) async {
          recognitions++;
          expect(prompt, contains('9053'));
          return jsonEncode({
            'rows': [
              {
                'time': time.toIso8601String(),
                'cardLast4': '9053',
                'delta': '-30.00',
              },
            ],
          });
        },
      );
      final service = ReconciliationService(
        store,
        recognizer: recognizer,
        engine: ReconciliationEngine(
          chat: (_) async => '{"proposals":[],"issues":[]}',
        ),
      );
      await service.analyze(session);
      expect(recognitions, 1);
      expect(session.rows.map((r) => r.delta).toSet(), {-200, -3000});
      expect(session.sources.single['accountCardLast4'], '9053');
      expect(
        session.sources.single['cardRecognitionVersion'],
        StatementRecognizer.cardRecognitionVersion,
      );
      await service.analyze(session);
      expect(recognitions, 1);
    },
  );

  test(
    'failed card re-recognition preserves previous evidence for retry',
    () async {
      session.accounts.single.cardLast4 = '9053';
      await expectLater(
        ReconciliationService(
          store,
          recognizer: StatementRecognizer(
            vision: (_, __) async => throw StateError('识别暂时失败'),
          ),
          engine: ReconciliationEngine(chat: (_) async => '{"proposals":[]}'),
        ).analyze(session),
        throwsStateError,
      );
      expect(session.rows.single.delta, -1000);
      expect(session.rows.single.sourceIds, ['image']);
      expect(session.sources.single['cardRecognitionVersion'], isNull);
    },
  );
}
