import 'dart:convert';
import 'dart:io';

import 'package:beecount/services/reconciliation/reconciliation_engine.dart';
import 'package:beecount/services/reconciliation/reconciliation_evidence.dart';
import 'package:beecount/services/reconciliation/reconciliation_models.dart';
import 'package:beecount/services/reconciliation/statement_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 9, 1);
  final baseline = DateTime.utc(2026, 9, 24);
  final time = DateTime.utc(2026, 9, 25, 8);
  final end = DateTime.utc(2026, 10, 9);
  ReconciliationSession session({bool knownBaseline = true}) =>
      ReconciliationSession(
        id: 'evidence',
        defaultLedgerId: 1,
        start: start,
        end: end,
        accounts: [
          ReconciliationAccount(
            id: 1,
            name: '微信',
            type: 'wechat',
            currency: 'CNY',
            balanceAt: end,
            actualBalance: 9000,
            complete: true,
            initialBalanceAt: knownBaseline ? baseline : null,
          ),
        ],
        rows: [
          StatementRow(
            id: 'r',
            accountId: 1,
            sourceIds: ['image'],
            time: time,
            delta: -1000,
            description: '商家',
          ),
        ],
      );
  Json transaction({int id = 1, String type = 'expense', int amount = 1000}) =>
      {
        'id': id,
        'ledgerId': 1,
        'accountId': 1,
        'type': type,
        'amountCents': amount,
        'happenedAt': time.toIso8601String(),
      };
  Json proposal({String certainty = 'supported'}) => {
    'title': '补记',
    'reason': '需核实用途',
    'certainty': certainty,
    'evidenceIds': ['r'],
    'mutations': [
      {
        'id': 'new',
        'after': {
          'ledgerId': 1,
          'accountId': 1,
          'type': 'expense',
          'amountCents': 1000,
          'happenedAt': time.toIso8601String(),
        },
      },
    ],
  };
  Future<void> analyze(
    ReconciliationSession s,
    ReconciliationChat chat, {
    List<Json> transactions = const [],
  }) => ReconciliationEngine(
    chat: chat,
  ).analyze(s, transactions, {1: 10000}, [], [], []);

  test('all bills never prove wallet funding; balance changes do', () async {
    final a = session().accounts.single;
    Future<StatementRow> recognize(String scope, String funding) async =>
        (await StatementRecognizer(
          vision: (_, __) async => jsonEncode({
            'statementScope': scope,
            'rows': [
              {
                'time': time.toIso8601String(),
                'delta': '-10.00',
                'fundingType': funding,
                'fundingDescription': funding == 'bank_card' ? '建设银行储蓄卡' : '',
              },
            ],
          }),
        ).recognize(File('unused.png'), {'id': 'image'}, a)).single;
    expect((await recognize('all_bills', 'unknown')).accountConfirmed, isFalse);
    expect(
      (await recognize('balance_changes', 'unknown')).accountConfirmed,
      isTrue,
    );
    expect(
      (await recognize('balance_changes', 'bank_card')).accountConfirmed,
      isFalse,
    );
    expect((await recognize('all_bills', 'wechat')).accountConfirmed, isTrue);
    final s = session()..rows = [await recognize('all_bills', 'unknown')];
    s.refreshEvidenceCompleteness();
    expect(s.accounts.single.complete, isFalse);
    await analyze(
      s,
      (_) async => throw StateError('unknown funding must not reach model'),
    );
    expect(s.matches, isEmpty);
    expect(s.proposals, isEmpty);
    expect(s.questions.any((q) => q['kind'] == 'funding'), isTrue);
  });

  test(
    'partial evidence supports a specific proposal without claiming full period',
    () async {
      final s = session();
      await analyze(
        s,
        (_) async => jsonEncode({
          'proposals': [proposal()],
        }),
      );
      expect(s.proposals, hasLength(1));
      final r = reconciliationReports(s, [], {1: 10000}).single;
      expect(r.periodDifference, isNull);
      expect(r.openingDifference, isNull);
      expect(r.status, contains('完整流水'));
      s.accounts.single.coverageStart = baseline;
      s.accounts.single.coverageEnd = end;
      s.proposals.single['selected'] = true;
      final complete = reconciliationReports(s, [], {1: 10000}).single;
      expect(complete.periodStart, baseline);
      expect(complete.projectedBalance, 9000);
      expect(complete.status, '已对齐');
    },
  );

  test(
    'unknown opening date cannot establish a historical difference',
    () async {
      final s = session(knownBaseline: false);
      s.accounts.single.actualBalance = 7000;
      s.accounts.single.coverageStart = start;
      s.accounts.single.coverageEnd = end;
      final tx = transaction();
      tx['happenedAt'] = baseline.toIso8601String();
      final r = reconciliationReports(s, [tx], {1: 12000}).single;
      expect(r.periodDifference, 0);
      expect(r.openingDifference, isNull);
      await analyze(s, (_) async => '{"proposals":[]}', transactions: [tx]);
      expect(s.questions.any((q) => q['kind'] == 'baseline'), isTrue);
    },
  );

  test(
    'old statement rows need a baseline and are then excluded from additions',
    () async {
      final s = session(knownBaseline: false);
      s.rows.single.time = start.add(const Duration(days: 10));
      final tx = transaction()..['happenedAt'] = baseline.toIso8601String();
      await analyze(
        s,
        (_) async => throw StateError('old history must not reach model'),
        transactions: [tx],
      );
      expect(s.questions.any((q) => q['kind'] == 'baseline'), isTrue);
      s.accounts.single.initialBalanceAt = baseline;
      await analyze(
        s,
        (_) async => throw StateError('history included in opening balance'),
        transactions: [tx],
      );
      expect(s.proposals, isEmpty);
      expect(s.issues.join(), contains('早于初始余额日期'));
    },
  );

  test(
    'model questions and low certainty suggestions cannot mutate the ledger',
    () async {
      for (final certainty in ['supported', 'needs_confirmation']) {
        final s = session();
        await analyze(
          s,
          (_) async => jsonEncode({
            'questions': certainty == 'supported'
                ? [
                    {
                      'text': '请确认用途',
                      'evidenceIds': ['r'],
                    },
                  ]
                : [],
            'proposals': [proposal(certainty: certainty)],
          }),
        );
        expect(s.proposals, isEmpty);
        expect(s.questions.any((q) => q['kind'] == 'purpose'), isTrue);
      }
    },
  );

  test(
    'answers persist, reach the model, and expire when referenced evidence changes',
    () async {
      final s = session();
      s.answers.add({
        'id': 'purpose:1:r',
        'kind': 'purpose',
        'accountId': 1,
        'evidenceIds': ['r'],
        'evidenceKey': answerEvidenceKey(s, ['r']),
        'answer': '这是我自己的消费，微信零钱支付',
      });
      s.invalidate();
      final saved = ReconciliationSession.fromJson(s.toJson());
      expect(currentReconciliationAnswers(saved), hasLength(1));
      await analyze(saved, (prompt) async {
        final input = jsonObject(
          jsonDecode(prompt.substring(prompt.indexOf('\n{') + 1)),
        );
        expect(
          jsonObjects(input['userAnswers']).single['answer'],
          contains('微信零钱支付'),
        );
        return jsonEncode({
          'proposals': [proposal()],
        });
      });
      expect(saved.proposals, hasLength(1));
      saved.rows.single.delta = -2000;
      expect(currentReconciliationAnswers(saved), isEmpty);
      expect(saved.answers, hasLength(1));
    },
  );

  test(
    'offsetting unmatched records cannot masquerade as completed reconciliation',
    () {
      final s = session();
      s.accounts.single.coverageStart = baseline;
      s.accounts.single.coverageEnd = end;
      s.matches.add({'evidenceId': 'r', 'transactionId': 1, 'accountId': 1});
      final r = reconciliationReports(
        s,
        [
          transaction(),
          transaction(id: 2, type: 'income', amount: 500),
          transaction(id: 3, amount: 500),
        ],
        {1: 10000},
      ).single;
      expect(r.remainingDifference, 0);
      expect(r.pendingRows, 0);
      expect(r.pendingRecords, 2);
      expect(r.status, contains('待核对'));
    },
  );

  test(
    'applied additions are counted as reconciled without projecting them twice',
    () {
      final s = session();
      s.accounts.single.coverageStart = baseline;
      s.accounts.single.coverageEnd = end;
      s.proposals = [
        {...proposal(), 'selected': true},
      ];
      s.audit = {
        'undone': false,
        'changes': [
          {'before': null, 'after': transaction()},
        ],
      };
      final r = reconciliationReports(
        s,
        [transaction()],
        {1: 10000},
        proposals: [],
      ).single;
      expect(r.projectedBalance, 9000);
      expect(r.pendingRecords, 0);
      expect(r.pendingRows, 0);
      expect(r.status, '已对齐');
    },
  );

  test(
    'reviewed transfer can cover both accounts without adding a second record',
    () async {
      final s = session();
      s.accounts.single.coverageStart = baseline;
      s.accounts.single.coverageEnd = end;
      s.rows.single.delta = 1000;
      s.rows.single.description = '转入';
      s.accounts.add(
        ReconciliationAccount(
          id: 2,
          name: '银行卡',
          type: 'bank_card',
          currency: 'CNY',
          balanceAt: end,
          initialBalanceAt: baseline,
          coverageStart: baseline,
          coverageEnd: end,
          actualBalance: 9000,
          complete: true,
        ),
      );
      s.rows.add(
        StatementRow(
          id: 'out',
          accountId: 2,
          sourceIds: ['bank'],
          time: time,
          delta: -1000,
          description: '转出',
        ),
      );
      final tx = {
        ...transaction(type: 'transfer'),
        'accountId': 2,
        'toAccountId': 1,
      };
      await ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'reviewedMatches': [
            {'evidenceId': 'r', 'transactionId': 1, 'reason': '转入对应'},
            {'evidenceId': 'out', 'transactionId': 1, 'reason': '转出对应'},
          ],
          'proposals': [],
        }),
      ).analyze(s, [tx], {1: 8000, 2: 10000}, [], [], []);
      expect(s.matches, hasLength(2));
      expect(s.proposals, isEmpty);
      expect(
        reconciliationReports(
          s,
          [tx],
          {1: 8000, 2: 10000},
        ).every((r) => r.status == '已对齐'),
        isTrue,
      );
    },
  );

  test(
    'model cannot confirm invented, wrong-direction or ambiguous matches',
    () async {
      for (final records in [
        [transaction(type: 'income')],
        [transaction(), transaction(id: 2)],
      ]) {
        final s = session();
        s.rows.single.description = '其他支付平台';
        for (final record in records) {
          record['merchant'] = '实际商家';
        }
        await analyze(
          s,
          (_) async => jsonEncode({
            'reviewedMatches': [
              {'evidenceId': 'r', 'transactionId': 1},
              {'evidenceId': 'r', 'transactionId': 999},
            ],
            'proposals': [],
          }),
          transactions: records,
        );
        expect(s.matches, isEmpty);
        expect(s.proposals, isEmpty);
      }
    },
  );

  test(
    'a question or low certainty proposal takes priority over a model match claim',
    () async {
      final s = session();
      s.rows.single.description = '其他支付平台';
      final tx = transaction()..['merchant'] = '实际商家';
      await analyze(
        s,
        (_) async => jsonEncode({
          'reviewedMatches': [
            {'evidenceId': 'r', 'transactionId': 1},
          ],
          'questions': [
            {
              'text': '是否同一笔付款？',
              'evidenceIds': ['r'],
            },
          ],
          'proposals': [],
        }),
        transactions: [tx],
      );
      expect(s.matches, isEmpty);
      expect(s.questions.any((q) => q['kind'] == 'purpose'), isTrue);
    },
  );
}
