import 'dart:convert';

import 'package:beecount/services/reconciliation/reconciliation_engine.dart';
import 'package:beecount/services/reconciliation/reconciliation_matcher.dart';
import 'package:beecount/services/reconciliation/reconciliation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 5, 3);
  StatementRow row(
    String id, {
    int account = 1,
    int delta = -1000,
    int seconds = 0,
    String description = '商家付款',
    String? order,
    String precision = 'second',
  }) => StatementRow(
    id: id,
    accountId: account,
    sourceIds: [id],
    time: at.add(Duration(seconds: seconds)),
    delta: delta,
    description: description,
    orderId: order,
    timePrecision: precision,
  );
  Json tx(
    int id, {
    int account = 1,
    int amount = 1000,
    int seconds = 0,
    String type = 'expense',
    int? to,
    String? note,
    String? merchant,
  }) => {
    'id': id,
    'ledgerId': 1,
    'syncId': 'sync$id',
    'accountId': account,
    'toAccountId': to,
    'amountCents': amount,
    'type': type,
    'note': note,
    'merchant': merchant,
    'happenedAt': at.add(Duration(seconds: seconds)).toIso8601String(),
  };
  ReconciliationSession session(List<StatementRow> rows) =>
      ReconciliationSession(
        id: 'test',
        defaultLedgerId: 1,
        start: at.subtract(const Duration(days: 1)),
        end: at.add(const Duration(days: 1)),
        rows: rows,
        accounts: [
          ReconciliationAccount(
            id: 1,
            name: '钱包',
            currency: 'CNY',
            balanceAt: at.add(const Duration(days: 1)),
            complete: true,
          ),
          ReconciliationAccount(
            id: 2,
            name: '银行卡',
            currency: 'CNY',
            balanceAt: at.add(const Duration(days: 1)),
            complete: true,
          ),
        ],
      );
  Json addition(String id, Json after) => {'id': id, 'after': after};

  test(
    'already recorded expense and income within seconds skip missing-record inference',
    () async {
      final rows = [
        row('a', delta: -14320, seconds: 9),
        row('b', delta: -1500),
        row('c', delta: 54720, seconds: 1),
        row('d', delta: 13680, seconds: 1),
      ];
      final records = [
        tx(1, amount: 14320),
        tx(2, amount: 1500),
        tx(3, amount: 54720, type: 'income'),
        tx(4, amount: 13680, type: 'income'),
      ];
      final s = session(rows);
      await ReconciliationEngine(
        chat: (_) async => throw StateError('all rows already match'),
      ).analyze(s, records, {}, [], [], []);
      expect(s.matches, hasLength(4));
      expect(s.proposals, isEmpty);
      expect(s.issues, isEmpty);
      expect(s.summary, contains('4 条已与账本记录匹配'));
    },
  );

  test('matching is one-to-one, signed and account-specific', () {
    expect(
      ReconciliationMatcher([row('a'), row('b')], [tx(1)]).confirmed,
      isEmpty,
    );
    expect(
      ReconciliationMatcher([row('a')], [tx(1), tx(2)]).confirmed,
      isEmpty,
    );
    expect(
      ReconciliationMatcher([row('a', account: 2)], [tx(1)]).confirmed,
      isEmpty,
    );
    expect(
      ReconciliationMatcher([row('a', delta: 1000)], [tx(1)]).confirmed,
      isEmpty,
    );
    expect(
      ReconciliationMatcher([row('a', seconds: 86400)], [tx(1)]).confirmed,
      isEmpty,
    );
  });

  test(
    'distinct merchants or full order numbers cannot be swallowed by equal amounts',
    () {
      expect(
        ReconciliationMatcher(
          [row('a', description: '商家甲')],
          [tx(1, merchant: '商家乙')],
        ).confirmed,
        isEmpty,
      );
      expect(
        ReconciliationMatcher(
          [row('a', order: '12345678901')],
          [tx(1, note: '订单号: 12345678902')],
        ).confirmed,
        isEmpty,
      );
      expect(
        ReconciliationMatcher(
          [row('a', order: '12345678901', seconds: 3600)],
          [tx(1, note: '订单号: 12345678901')],
        ).confirmed,
        hasLength(1),
      );
    },
  );

  test(
    'transfers and legacy income refunds retain semantic review candidates',
    () {
      final transfer = tx(1, type: 'transfer', to: 2);
      final rows = [row('out'), row('in', account: 2, delta: 1000)];
      final matcher = ReconciliationMatcher(rows, [transfer]);
      expect(matcher.confirmed, isEmpty);
      expect(matcher.comparison(rows.last)['sameAccountAndDirectionIds'], [1]);
      final refund = row('refund', delta: 1000, description: '火车票退款');
      expect(
        ReconciliationMatcher([refund], [tx(1, type: 'income')]).confirmed,
        isEmpty,
      );
    },
  );

  test(
    'model additions with a nearby recorded candidate become checks, not executable omissions',
    () async {
      final s = session([row('a', delta: -440, seconds: 1800)]);
      await ReconciliationEngine(
        chat: (prompt) async {
          final data = jsonObject(
            jsonDecode(prompt.substring(prompt.indexOf('\n{') + 1)),
          );
          expect(
            jsonObjects(
              data['rowComparisons'],
            ).single['sameAccountAndDirectionIds'],
            [1],
          );
          expect(
            jsonObjects(data['localTransactions']).single['amountText'],
            '4.40',
          );
          return jsonEncode({
            'summary': '本地缺少这笔支出',
            'issues': [
              {
                'text': '本地缺少这笔支出',
                'evidenceIds': ['a'],
              },
            ],
            'proposals': [
              {
                'title': '补记',
                'evidenceIds': ['a'],
                'mutations': [
                  addition('new', tx(2, amount: 440, seconds: 1800)),
                ],
              },
            ],
          });
        },
      ).analyze(s, [tx(1, amount: 440)], {}, [], [], []);
      expect(s.proposals, isEmpty);
      expect(s.issues.single, contains('#1'));
      expect(s.summary, isNot(contains('本地缺少')));
    },
  );

  test(
    'boundary records remain candidates rather than creating duplicate additions',
    () async {
      final s = session([row('a', seconds: 86400)])
        ..start = at.add(const Duration(seconds: 86400));
      final existing = tx(1, seconds: 86391);
      await ReconciliationEngine(
        chat: (_) async => throw StateError('already recorded'),
      ).analyze(s, [existing], {}, [], [], []);
      expect(s.matches, hasLength(1));
    },
  );

  test(
    'addition guards both transfer legs, projected changes and within-plan duplicates',
    () {
      final transfer = tx(1, type: 'transfer', to: 2);
      expect(
        () => assertNoDuplicateAdditions(
          [addition('new', tx(2, account: 2, type: 'income'))],
          [transfer],
        ),
        throwsStateError,
      );
      expect(
        () => assertNoDuplicateAdditions([
          addition('a', tx(2)),
          addition('b', tx(3)),
        ], []),
        throwsStateError,
      );
      // Reclassifying a transfer removes its old legs before assessing additions.
      expect(
        () => assertNoDuplicateAdditions(
          [
            {'id': 'replace', 'transactionId': 1, 'after': tx(1)},
            addition('income', tx(2, account: 2, type: 'income')),
          ],
          [transfer],
        ),
        returnsNormally,
      );
      expect(
        () => assertNoDuplicateAdditions(
          [
            {'id': 'edit', 'transactionId': 1, 'after': tx(1)},
            addition('duplicate', tx(2)),
          ],
          [transfer],
        ),
        throwsStateError,
      );
      expect(
        () => assertNoDuplicateAdditions(
          [addition('new', tx(2, merchant: '乙'))],
          [tx(1, merchant: '甲')],
        ),
        returnsNormally,
      );
    },
  );

  test(
    'real omissions are retained and dated corrections modify the existing record',
    () async {
      final s = session([
        row('missing', delta: -2200),
        row('dated', seconds: 1800),
      ]);
      await ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'proposals': [
            {
              'title': '新增',
              'evidenceIds': ['missing'],
              'mutations': [addition('new', tx(2, amount: 2200))],
            },
            {
              'title': '修正时间',
              'evidenceIds': ['dated'],
              'mutations': [
                {
                  'id': 'edit',
                  'transactionId': 1,
                  'after': tx(1, seconds: 1800),
                },
              ],
            },
          ],
        }),
      ).analyze(s, [tx(1)], {}, [], [], []);
      expect(s.proposals, hasLength(2));
      expect(s.proposals.last['mutations'].single['transactionId'], 1);
    },
  );

  test(
    'old reports require fresh analysis while evidence and applied audits survive',
    () {
      final s = session([row('a')])..fingerprint = 'same';
      final old = ReconciliationSession.fromJson(
        s.toJson()..remove('analysisVersion'),
      );
      expect(old.hasCurrentAnalysis('same'), isFalse);
      old.analysisVersion = reconciliationAnalysisVersion;
      expect(old.hasCurrentAnalysis('same'), isTrue);
      expect(old.hasCurrentAnalysis('changed'), isFalse);
      old.invalidate();
      expect(old.rows, hasLength(1));
      expect(old.matches, isEmpty);
      expect(old.analysisVersion, 0);
    },
  );
  test(
    'a bulk group retains genuine omissions while rejecting existing dated entries',
    () async {
      final s = session([
        row('existing', seconds: 36000),
        row('missing', delta: -2200),
      ]);
      await ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'proposals': [
            {
              'title': '全部漏记',
              'evidenceIds': ['existing', 'missing'],
              'mutations': [
                addition('duplicate', tx(2, seconds: 36000)),
                addition('real', tx(3, amount: 2200)),
              ],
            },
          ],
        }),
      ).analyze(s, [tx(1)], {}, [], [], []);
      expect(s.proposals, hasLength(1));
      expect(s.proposals.single['evidenceIds'], ['missing']);
      expect(
        s.proposals.single['mutations'].single['after']['amountCents'],
        2200,
      );
      expect(s.issues.single, contains('#1'));
    },
  );
  test(
    'truncated JSON automatically splits the batch without dropping primary rows',
    () async {
      final s = session(
        List.generate(4, (i) => row('r$i', delta: -(i + 1) * 100)),
      );
      final handled = <String>[];
      var calls = 0;
      await ReconciliationEngine(
        chat: (prompt) async {
          calls++;
          final data = jsonObject(
            jsonDecode(prompt.substring(prompt.indexOf('\n{') + 1)),
          );
          final ids = List<String>.from(data['primaryIds']);
          if (ids.length > 2) return '{"proposals":[{"reason":"cut';
          handled.addAll(ids);
          return '{"summary":"已核对","proposals":[],"issues":[]}';
        },
      ).analyze(s, [], {}, [], [], []);
      expect(calls, 3);
      expect(handled, ['r0', 'r1', 'r2', 'r3']);
    },
  );

  test('optional summary failure preserves all validated results', () async {
    final s = session(
      List.generate(13, (i) => row('r$i', delta: -(i + 1) * 100)),
    );
    var calls = 0;
    await ReconciliationEngine(
      chat: (prompt) async {
        calls++;
        if (!prompt.contains('primaryIds')) {
          throw StateError('summary unavailable');
        }
        return '{"proposals":[],"issues":[]}';
      },
    ).analyze(s, [], {}, [], [], []);
    expect(calls, 3);
    expect(s.summary, contains('已生成 0 组修改建议'));
    expect(s.summary, contains('13 条流水'));
  });

  test(
    'platform and merchant aliases remain candidates and cannot justify double additions',
    () {
      final r = row('a', description: '平台付款-收款企业');
      final t = tx(1, merchant: '平台店铺名称');
      final matcher = ReconciliationMatcher([r], [t]);
      expect(matcher.confirmed, isEmpty);
      expect(matcher.comparison(r)['sameAccountAndDirectionIds'], [1]);
      expect(
        () => matcher.checkAdditions(
          [addition('new', tx(2, merchant: '收款企业'))],
          [r],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'date-only evidence matches a unique known merchant without replacing payment time',
    () {
      final r = row('a', description: '铁路12306', precision: 'day');
      final matcher = ReconciliationMatcher(
        [r],
        [tx(1, seconds: 3600, merchant: '铁路12306')],
      );
      expect(matcher.confirmed, hasLength(1));
      expect(
        ReconciliationMatcher([r], [tx(1, seconds: 3600)]).confirmed,
        isEmpty,
      );
      expect(
        ReconciliationMatcher(
          [r],
          [
            tx(1, seconds: 3600, merchant: '铁路12306'),
            tx(2, seconds: 7200, merchant: '铁路12306'),
          ],
        ).confirmed,
        isEmpty,
      );
    },
  );

  test(
    'coarse time cannot turn an existing exact time into midnight or fabricated seconds',
    () async {
      final r = row('a', precision: 'day');
      final existing = tx(1, seconds: 3600);
      final s = session([r]);
      await ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'summary': '需要修正零点时间',
          'proposals': [
            {
              'title': '修正时间',
              'evidenceIds': ['a'],
              'mutations': [
                {'id': 'edit', 'transactionId': 1, 'after': tx(1)},
              ],
            },
          ],
        }),
      ).analyze(s, [existing], {}, [], [], []);
      expect(s.proposals, isEmpty);
      expect(s.summary, isNot(contains('需要修正零点时间')));
      final changed = session([row('a', delta: -2200, precision: 'day')]);
      await ReconciliationEngine(
        chat: (_) async => jsonEncode({
          'proposals': [
            {
              'title': '修正金额',
              'evidenceIds': ['a'],
              'mutations': [
                {
                  'id': 'edit',
                  'transactionId': 1,
                  'after': tx(1, amount: 2200),
                },
              ],
            },
          ],
        }),
      ).analyze(
        changed,
        [
          {...existing, 'merchant': '商家付款'},
        ],
        {},
        [],
        [],
        [],
      );
      expect(
        changed.proposals.single['mutations'].single['after']['amountCents'],
        2200,
      );
      expect(
        changed.proposals.single['mutations'].single['after']['happenedAt'],
        existing['happenedAt'],
      );
    },
  );

  test(
    'legacy cached midnight is coarse but manual midnight remains explicit',
    () {
      final data = row('a', seconds: -39600).toJson()..remove('timePrecision');
      expect(StatementRow.fromJson(data).timePrecision, 'day');
      data['sourceIds'] = <String>[];
      expect(StatementRow.fromJson(data).timePrecision, 'second');
      data['timePrecision'] = 'minute';
      expect(StatementRow.fromJson(data).timePrecision, 'minute');
    },
  );

  test(
    'same-amount reimbursement cannot overwrite a separate recorded expense',
    () {
      final incoming = row(
        'reimbursement',
        account: 2,
        delta: 5150,
        description: '转账-来自朋友',
      );
      final existing = tx(1, amount: 5150, merchant: '火锅鸡');
      final matcher = ReconciliationMatcher([incoming], [existing]);
      expect(
        () => matcher.checkCorrections(
          [
            {
              'id': 'change',
              'transactionId': 1,
              'after': tx(1, account: 2, amount: 5150, type: 'income'),
            },
          ],
          [incoming],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'date-only unrelated amount cannot replace a recorded discounted purchase',
    () {
      final r = row(
        'purchase',
        delta: -13444,
        precision: 'day',
        description: '京东理然个护',
      );
      final existing = tx(1, amount: 1, seconds: 3600, merchant: '京东健康');
      expect(
        () => ReconciliationMatcher([r], [existing]).checkCorrections(
          [
            {'id': 'change', 'transactionId': 1, 'after': tx(1, amount: 13444)},
          ],
          [r],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'refund reclassification preserves positive balance movement and matching original link',
    () {
      final r = row('refund', delta: 800, description: '拼多多退款');
      final existing = tx(1, amount: 800, type: 'income');
      expect(
        () => ReconciliationMatcher([r], [existing]).checkCorrections(
          [
            {
              'id': 'change',
              'transactionId': 1,
              'after': {...tx(1, amount: -800), 'refundOfSyncId': 'original'},
            },
          ],
          [r],
        ),
        returnsNormally,
      );
    },
  );
}
