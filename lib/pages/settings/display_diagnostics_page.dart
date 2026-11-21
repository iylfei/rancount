import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/font_scale_provider.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/ui/ui.dart';

class DisplayDiagnosticsPage extends StatelessWidget {
  const DisplayDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BeeTokens.scaffoldBackground(context),
    body: Column(
      children: [
        PrimaryHeader(
          title: AppLocalizations.of(context).displayDiagnosticsTitle,
          showBack: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: const [_DisplayScaleInfo()],
          ),
        ),
      ],
    ),
  );
}

// UI缩放信息显示组件
class _DisplayScaleInfo extends ConsumerWidget {
  const _DisplayScaleInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugInfo = ref.watch(uiScaleDebugProvider(context));
    final theme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(12.0.scaled(context, ref)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).fontSettingsScreenInfo,
              style: theme.titleMedium,
            ),
            SizedBox(height: 8.0.scaled(context, ref)),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsScreenDensity,
              debugInfo['devicePixelRatio']!.toStringAsFixed(2),
            ),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsScreenWidth,
              '${debugInfo['screenWidth']!.toStringAsFixed(0)}dp',
            ),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsDeviceScale,
              'x${debugInfo['deviceScaleFactor']!.toStringAsFixed(2)}',
            ),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsUserScale,
              'x${debugInfo['userScaleFactor']!.toStringAsFixed(2)}',
            ),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsFinalScale,
              'x${debugInfo['finalScaleFactor']!.toStringAsFixed(2)}',
            ),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsBaseDevice,
              debugInfo['isBaseDevice']! > 0.5
                  ? AppLocalizations.of(context).fontSettingsYes
                  : AppLocalizations.of(context).fontSettingsNo,
            ),
            _infoRow(
              context,
              AppLocalizations.of(context).fontSettingsRecommendedScale,
              'x${debugInfo['recommendedUserScale']!.toStringAsFixed(2)}',
            ),
            SizedBox(height: 8.0.scaled(context, ref)),
            Container(
              padding: EdgeInsets.all(8.0.scaled(context, ref)),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24.0.scaled(context, ref),
                    height: 24.0.scaled(context, ref),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8.0.scaled(context, ref)),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).fontSettingsScaleExample,
                      style: theme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: BeeTokens.textTertiary(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: BeeTokens.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
