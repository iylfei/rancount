import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/automation/image_draft_page.dart';
import 'package:beecount/pages/transaction/transaction_editor_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/widgets/biz/amount_editor_sheet.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.ensureSeed();
  });

  tearDown(() async => db.close());

  Widget wrap(Widget home, {int ledgerId = 1}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        repositoryProvider.overrideWithValue(repo),
        currentLedgerIdProvider.overrideWith((ref) => ledgerId),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: home,
      ),
    );
  }

  testWidgets('采集失败态展示上传截图与手动记账，点手动记账以 quickAdd 打开并可弹出金额输入', (
    tester,
  ) async {
    int? savedLedgerId;
    var closed = false;

    await tester.pumpWidget(
      wrap(
        ImageDraftPage(
          initialError: '截屏采集失败，请上传截图或手动记账',
          onSaved: (ledgerId) async => savedLedgerId = ledgerId,
          onClose: () async => closed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('截屏采集失败，请上传截图或手动记账'), findsOneWidget);
    expect(find.text('上传截图识别记账'), findsOneWidget);
    expect(find.text('手动记账'), findsOneWidget);

    await tester.tap(find.text('手动记账'));
    await tester.pumpAndSettle();

    final editorFinder = find.byType(TransactionEditorPage);
    expect(editorFinder, findsOneWidget);
    final editor = tester.widget<TransactionEditorPage>(editorFinder);
    expect(editor.quickAdd, isTrue);
    expect(editor.showImageBillingAction, isFalse);

    // 验证选择分类后会弹出金额输入页（旧 bug 会直接 pop 回失败页）
    final categories = await repo.getAllCategories();
    final expenseCat = categories.firstWhere(
      (c) => c.kind == 'expense' && c.level == 1,
    );
    await tester.tap(find.text(expenseCat.name).first);
    await tester.pumpAndSettle();

    expect(find.byType(AmountEditorSheet), findsOneWidget);
    expect(savedLedgerId, isNull);
    expect(closed, isFalse);

    // 卸载树并推进时钟，释放 Drift stream 与 LoggerService 2s 防抖定时器
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('从底部加号进入新建记账页时顶栏展示上传截图识别入口', (tester) async {
    await tester.pumpWidget(
      wrap(
        const TransactionEditorPage(initialKind: 'expense', quickAdd: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('上传截图识别记账'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
