import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/services/reconciliation/reconciliation_engine.dart';
import 'package:beecount/services/reconciliation/reconciliation_models.dart';
import 'package:beecount/services/reconciliation/statement_recognizer.dart';

void main() {
  final start = DateTime.utc(2026, 10, 1);
  final end = DateTime.utc(2026, 10, 9);
  ReconciliationSession session() => ReconciliationSession(
    id: 'test',
    defaultLedgerId: 1,
    start: start,
    end: end,
    accounts: [
      ReconciliationAccount(
        id: 1,
        name: '钱包',
        currency: 'CNY',
        balanceAt: end,
        actualBalance: 8000,
        complete: true,
      ),
    ],
  );

  test('money is exact and unknown evidence does not acquire defaults', () {
    expect(moneyCents('-143.20'), -14320);
    expect(moneyCents('0.10'), 10);
    expect(moneyCents(null), isNull);
    expect(() => moneyCents('1.234'), throwsFormatException);
    expect(evidenceTime(null), isNull);
    expect(evidenceTime('2026-02-30 10:30:55'), isNull);
    expect(evidenceTime('2026-10-08 25:30:55'), isNull);
    expect(
      evidenceTime('2026-10-08 10:30:55'),
      DateTime.utc(2026, 10, 8, 2, 30, 55),
    );
  });

  test(
    'debt input is positive while stored balances retain accounting signs',
    () {
      final a = ReconciliationAccount(
        id: 3,
        name: '花呗',
        type: 'credit_card',
        currency: 'CNY',
        balanceAt: end,
      );
      expect(a.balanceFromInput('123.45'), -12345);
      expect(a.balanceFromInput('0'), 0);
      expect(a.balanceFromInput(''), isNull);
      expect(() => a.balanceFromInput('-1'), throwsFormatException);
      expect(a.displayBalance(-12345), 12345);
      expect(a.deltaText(-100), '欠款增加 1.00');
      expect(a.deltaText(100), '欠款减少 1.00');
      expect(ReconciliationAccount.fromJson(a.toJson()).isLiability, isTrue);
    },
  );

  test(
    'missing evidence defaults to no movement without fabricating balance',
    () async {
      final s = session();
      s.accounts.single.actualBalance = null;
      s.refreshEvidenceCompleteness();
      final txs = <Json>[
        {
          'id': 7,
          'type': 'expense',
          'amountCents': 1000,
          'accountId': 1,
          'happenedAt': start.toIso8601String(),
        },
      ];
      final r = reconciliationReports(s, txs, {1: 10000}).single;
      expect(r.periodDifference, 1000);
      expect(r.actualBalance, isNull);
      expect(r.openingDifference, isNull);
      await ReconciliationEngine(
        chat: (_) async => throw StateError('no AI needed'),
      ).analyze(s, txs, {1: 10000}, [], [], []);
      expect(s.proposals, isEmpty);
      expect(s.summary, contains('无余额变动'));
      expect(s.issues.any((i) => i.contains('#7')), isTrue);
    },
  );

  test(
    'unreadable uploads remain incomplete; valid manual rows are evidence',
    () {
      final s = session();
      s.sources = [
        {'id': 'a', 'accountId': 1, 'recognized': false},
      ];
      s.refreshEvidenceCompleteness();
      expect(s.accounts.single.complete, isFalse);
      s.sources.single['recognized'] = true;
      s.sources.single['warnings'] = ['未识别到交易'];
      s.refreshEvidenceCompleteness();
      expect(s.accounts.single.complete, isFalse);
      s.sources.clear();
      s.rows.add(
        StatementRow(
          id: 'm',
          accountId: 1,
          sourceIds: [],
          time: start,
          delta: -100,
        ),
      );
      s.refreshEvidenceCompleteness();
      expect(s.accounts.single.complete, isTrue);
      s.rows.single.delta = null;
      s.refreshEvidenceCompleteness();
      expect(s.accounts.single.complete, isFalse);
    },
  );

  test(
    'credit screenshot uses total debt and signs for repayment and consumption',
    () async {
      final a = ReconciliationAccount(
        id: 3,
        name: '花呗',
        type: 'credit_card',
        currency: 'CNY',
        balanceAt: end,
      );
      final rows = await StatementRecognizer(
        vision: (_, prompt) async {
          expect(prompt, contains('包括未出账'));
          expect(prompt, contains('还款、退款'));
          expect(prompt, contains('不能用作 balanceAfter'));
          return jsonEncode({
            'rows': [
              {
                'time': '2026-10-05T08:00:00+08:00',
                'delta': '-20.00',
                'balanceAfter': '-120.00',
              },
              {
                'time': '2026-10-05T09:00:00+08:00',
                'delta': '50.00',
                'balanceAfter': '-70.00',
              },
            ],
          });
        },
      ).recognize(File('unused.png'), {'id': 'a'}, a);
      expect(rows.map((r) => r.delta), [-2000, 5000]);
      expect(rows.last.balanceAfter, -7000);
    },
  );

  test('overlap merge preserves two identical rows from one screenshot', () {
    StatementRow row(String id, String source) => StatementRow(
      id: id,
      accountId: 1,
      sourceIds: [source],
      time: start,
      delta: -100,
      balanceAfter: 200,
      description: '商家',
    );
    final rows = mergeStatementRows([
      row('a1', 'a'),
      row('a2', 'a'),
      row('b1', 'b'),
      row('b2', 'b'),
    ]);
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.sourceIds.length == 2), isTrue);
    expect(
      mergeStatementRows([
        StatementRow(id: 'x', accountId: 1, sourceIds: ['a']),
        StatementRow(id: 'y', accountId: 1, sourceIds: ['b']),
      ]),
      hasLength(2),
    );
  });

  test(
    'same mixed screenshot is partitioned by actual card, not upload account',
    () async {
      final mixed = jsonEncode({
        'rows': [
          {
            'time': '2026-10-05T00:00:00+08:00',
            'timePrecision': 'day',
            'cardLast4': '9053',
            'cardKind': 'bank_card',
            'description': '储蓄卡消费',
            'delta': '-10.00',
          },
          {
            'time': '2026-10-05T09:00:00+08:00',
            'timePrecision': 'minute',
            'cardLast4': '0803',
            'cardKind': 'credit_card',
            'description': '信用卡消费',
            'delta': '-20.00',
          },
        ],
      });
      final recognizer = StatementRecognizer(
        vision: (_, prompt) async {
          expect(prompt, contains('上传位置不能证明'));
          return mixed;
        },
      );
      final debit = ReconciliationAccount(
        id: 1,
        name: '储蓄卡',
        type: 'bank_card',
        currency: 'CNY',
        cardLast4: '9053',
        balanceAt: end,
      );
      final credit = ReconciliationAccount(
        id: 2,
        name: '信用卡',
        type: 'credit_card',
        currency: 'CNY',
        cardLast4: '0803',
        balanceAt: end,
      );
      final a = <String, dynamic>{'id': 'debit'};
      final b = <String, dynamic>{'id': 'credit'};
      final debitRows = await recognizer.recognize(File('same.png'), a, debit);
      final creditRows = await recognizer.recognize(
        File('same.png'),
        b,
        credit,
      );
      expect(debitRows.single.delta, -1000);
      expect(debitRows.single.timePrecision, 'day');
      expect(creditRows.single.delta, -2000);
      expect(creditRows.single.timePrecision, 'minute');
      expect(a['excludedOtherCards'], 1);
      expect(b['excludedOtherCards'], 1);
      expect(ReconciliationAccount.fromJson(debit.toJson()).cardLast4, '9053');
    },
  );

  test(
    'unidentified card remains visible but cannot become an executable suggestion',
    () async {
      final a = ReconciliationAccount(
        id: 1,
        name: '银行卡',
        type: 'bank_card',
        currency: 'CNY',
        cardLast4: '9053',
        balanceAt: end,
      );
      final rows = await StatementRecognizer(
        vision: (_, __) async => jsonEncode({
          'rows': [
            {'time': '2026-10-05T09:00:00+08:00', 'delta': '-10.00'},
          ],
        }),
      ).recognize(File('same.png'), {'id': 'a'}, a);
      expect(rows.single.warnings, contains('未确认交易用卡尾号，请核对账户归属'));
      final s = session()
        ..accounts = [a]
        ..rows = rows;
      await ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'proposals': [
            {
              'title': '补记消费',
              'evidenceIds': [rows.single.id],
              'mutations': [
                {
                  'id': 'new',
                  'after': {
                    'ledgerId': 1,
                    'type': 'expense',
                    'accountId': 1,
                    'amountCents': 1000,
                    'happenedAt': rows.single.time!.toIso8601String(),
                  },
                },
              ],
            },
          ],
        }),
      ).analyze(s, [], {}, [], [], []);
      expect(s.proposals, isEmpty);
      expect(s.issues.join(), contains('银行卡归属未确认'));
      expect(s.issues.join(), isNot(contains('补记消费：')));
    },
  );

  test('opening difference is separated from period omission', () {
    final s = session()
      ..rows = [
        StatementRow(
          id: 'one',
          accountId: 1,
          sourceIds: ['a'],
          time: start.add(const Duration(days: 1)),
          delta: -2000,
          balanceAfter: 8000,
        ),
      ];
    final txs = <Json>[
      {
        'id': 1,
        'accountId': 1,
        'type': 'expense',
        'amountCents': 1000,
        'happenedAt': start.add(const Duration(days: 1)).toIso8601String(),
      },
    ];
    final report = reconciliationReports(s, txs, {1: 12000}).single;
    expect(report.bookBalance, 11000);
    expect(report.periodDifference, -1000);
    expect(report.openingDifference, -2000);
    s.proposals = [
      {
        'selected': true,
        'mutations': [
          {
            'id': 'fix',
            'transactionId': 1,
            'after': {...txs.single, 'amountCents': 2000},
          },
        ],
      },
    ];
    expect(
      reconciliationReports(s, txs, {1: 12000}).single.projectedBalance,
      10000,
    );
  });

  test('incomplete and discontinuous screenshots cannot establish history', () {
    final s = session()
      ..rows = [
        StatementRow(
          id: 'a',
          accountId: 1,
          sourceIds: ['a'],
          time: start,
          delta: 1000,
          balanceAfter: 9000,
        ),
        StatementRow(
          id: 'b',
          accountId: 1,
          sourceIds: ['b'],
          time: end,
          delta: -100,
          balanceAfter: 8000,
        ),
      ];
    final report = reconciliationReports(s, [], {1: 0}).single;
    expect(report.openingDifference, isNull);
    expect(report.warnings.any((w) => w.contains('不连续')), isTrue);
    s.accounts.single.complete = false;
    expect(
      reconciliationReports(s, [], {1: 0}).single.periodDifference,
      isNull,
    );
  });

  test('refund increases balance and transfers conserve selected accounts', () {
    final s = session();
    s.accounts.add(
      ReconciliationAccount(
        id: 2,
        name: '银行卡',
        currency: 'CNY',
        balanceAt: end,
      ),
    );
    final txs = <Json>[
      {
        'id': 1,
        'accountId': 1,
        'toAccountId': 2,
        'type': 'transfer',
        'amountCents': 2500,
        'happenedAt': start.toIso8601String(),
      },
      {
        'id': 2,
        'accountId': 1,
        'type': 'expense',
        'amountCents': -500,
        'happenedAt': start.toIso8601String(),
      },
    ];
    final reports = reconciliationReports(s, txs, {1: 10000, 2: 0});
    expect(reports[0].bookBalance, 8000);
    expect(reports[1].bookBalance, 2500);
  });

  test(
    'all batches include opposite-account peers and no row is truncated',
    () async {
      final s = session();
      s.accounts.add(
        ReconciliationAccount(
          id: 2,
          name: '银行卡',
          currency: 'CNY',
          balanceAt: end,
        ),
      );
      s.rows = List.generate(
        45,
        (i) => StatementRow(
          id: 'r$i',
          accountId: i == 44 ? 2 : 1,
          sourceIds: ['a'],
          time: start.add(Duration(minutes: i)),
          delta: i == 44 ? 100 : -100,
        ),
      );
      final primary = <String>[];
      var calls = 0;
      final engine = ReconciliationEngine(
        chat: (prompt) async {
          calls++;
          if (prompt.contains('primaryIds')) {
            final data = jsonObject(
              jsonDecode(prompt.substring(prompt.indexOf('\n{') + 1)),
            );
            primary.addAll(List<String>.from(data['primaryIds']));
            if (calls == 1) {
              expect(
                jsonObjects(data['externalRows']).any((r) => r['id'] == 'r44'),
                isTrue,
              );
            }
            return '{"summary":"分批结果","issues":[],"proposals":[]}';
          }
          return '{"summary":"完整报告"}';
        },
      );
      await engine.analyze(s, [], {1: 0, 2: 0}, [], [], []);
      expect(primary.toSet(), hasLength(45));
      expect(calls, 5);
      expect(s.summary, contains('完整报告'));
    },
  );

  test(
    'invented evidence and invalid money cannot enter executable proposals',
    () async {
      final s = session()
        ..rows = [
          StatementRow(
            id: 'one',
            accountId: 1,
            sourceIds: ['a'],
            time: start,
            delta: -100,
          ),
        ];
      final engine = ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'proposals': [
            {
              'evidenceIds': ['unknown'],
              'mutations': [
                {'id': 'a', 'after': null},
              ],
            },
            {
              'evidenceIds': ['one'],
              'mutations': [
                {
                  'id': 'b',
                  'after': {
                    'ledgerId': 1,
                    'type': 'expense',
                    'amountCents': 'bad',
                    'happenedAt': start.toIso8601String(),
                  },
                },
              ],
            },
          ],
        }),
      );
      await engine.analyze(s, [], {1: 0}, [], [], []);
      expect(s.proposals, isEmpty);
      expect(s.issues, hasLength(2));
    },
  );
}
