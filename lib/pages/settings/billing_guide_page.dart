import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/app_list_tile.dart';
import '../../widgets/ui/ui.dart';
import '../ai/ai_settings_page.dart';
import '../automation/auto_billing_settings_page.dart';
import 'shortcuts_guide_page.dart';

class BillingGuidePage extends StatelessWidget {
  const BillingGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: l10n.billingGuideTitle, showBack: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (Platform.isAndroid) ...[
                  _GuideSection(
                    title: l10n.billingGuideScreenshotTitle,
                    description: l10n.billingGuideScreenshotAndroid,
                    actionLabel: l10n.aiSettingsTitle,
                    destination: const AISettingsPage(),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AutoBillingSettingsPage(),
                      ),
                    ),
                    child: Text(l10n.billingGuideScreenshotSettings),
                  ),
                  const SizedBox(height: 16),
                ],
                _GuideSection(
                  title: l10n.billingGuideImagesTitle,
                  description: Platform.isAndroid
                      ? l10n.billingGuideImagesAndroid
                      : l10n.billingGuideImagesIos,
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 16),
                  _GuideSection(
                    title: l10n.shareBilling,
                    description: l10n.billingGuideShareAndroid,
                  ),
                ],
                const SizedBox(height: 16),
                _GuideSection(
                  title: l10n.smartBillingVoiceBilling,
                  description: l10n.billingGuideVoice,
                  actionLabel: l10n.aiSettingsTitle,
                  destination: const AISettingsPage(),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: AppListTile(
                    leading: Icons.app_shortcut,
                    title: l10n.shortcutsGuide,
                    subtitle: l10n.shortcutsGuideDesc,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ShortcutsGuidePage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.title,
    required this.description,
    this.actionLabel,
    this.destination,
  });

  final String title;
  final String description;
  final String? actionLabel;
  final Widget? destination;

  @override
  Widget build(BuildContext context) => SectionCard(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(description),
          if (destination != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => destination!)),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}
