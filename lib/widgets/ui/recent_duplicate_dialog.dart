import 'package:flutter/material.dart';

import '../../data/repositories/local/local_repository.dart';
import '../../services/billing/recent_duplicate_service.dart';
import 'bee_alert_dialog.dart';

Future<bool> confirmRecentDuplicate({
  required BuildContext context,
  required LocalRepository repository,
  required double amount,
}) async {
  final duplicate = await RecentDuplicateService.exists(
    repository: repository,
    amount: amount,
  );
  if (!context.mounted) return false;
  if (!duplicate) return true;

  final isChinese = Localizations.localeOf(context).languageCode == 'zh';
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => BeeAlertDialog(
          title: Text(isChinese ? '疑似重复记账' : 'Possible duplicate'),
          content: Text(
            isChinese
                ? '最近 24 小时已有一笔相同金额（${amount.abs().toStringAsFixed(2)}）的账单。仍要保存吗？'
                : 'A transaction with the same amount (${amount.abs().toStringAsFixed(2)}) exists in the past 24 hours. Save anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(isChinese ? '返回检查' : 'Review'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isChinese ? '仍然保存' : 'Save anyway'),
            ),
          ],
        ),
      ) ??
      false;
}
