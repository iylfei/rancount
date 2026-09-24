import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/ai/core/json_response_parser.dart';
import 'package:beecount/services/billing/image_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('concurrent store instances preserve independent drafts', () async {
    await Future.wait(List.generate(8, (i) => ImageDraftStore().put(
        ImageDraftSession(id: 'draft-$i', ledgerId: 1,
            createdAt: DateTime(2026, 9, 1), entries: const []))));
    expect(await ImageDraftStore().load(), hasLength(8));
  });

  test('draft parser keeps missing values and all independent transactions',
      () {
    final bills = const JsonResponseParser().parseDraft('''[
      {"type":"expense","amount":-25,"merchant":"咖啡店","account":null},
      {"type":"expense","amount":-8,"time":"2026-09-23T09:00:00",
       "payment_channel":"微信支付","account":"招商银行卡"}
    ]''');
    expect(bills, hasLength(2));
    expect(bills.first.time, isNull);
    expect(bills.first.account, isNull);
    expect(bills.last.paymentChannel, '微信支付');
    expect(bills.last.account, '招商银行卡');
  });

  test('local draft retains user corrections and save state without an image',
      () async {
    final store = ImageDraftStore();
    final draft = ImageDraftSession(
      id: 'draft-1',
      ledgerId: 1,
      createdAt: DateTime(2026, 9, 23),
      entries: const [
        ImageDraftEntry(
          id: 'tx-1',
          bill: BillInfo(type: BillType.expense, amount: -25),
        ),
      ],
    );
    await store.put(draft);
    final changed = draft.copyWith(entries: [
      draft.entries.first.copyWith(
        bill: const BillInfo(
          type: BillType.expense,
          amount: -26,
          account: '零钱',
          category: '餐饮',
        ),
        saved: true,
      ),
    ]);
    await store.put(changed);
    final loaded = (await store.load()).single;
    expect(loaded.entries, hasLength(1));
    expect(loaded.entries.single.bill.amount, -26);
    expect(loaded.entries.single.bill.account, '零钱');
    expect(loaded.entries.single.saved, isTrue);
    await store.remove(loaded.id);
    expect(await store.load(), isEmpty);
  });
}
