import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/rancount_links.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/biz/app_list_tile.dart';
import '../../widgets/ui/ui.dart';
import 'billing_guide_page.dart';

class RanCountHelpPage extends StatelessWidget {
  const RanCountHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.mineHelp,
            subtitle: l10n.rancountHelpSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppListTile(
                        leading: Icons.menu_book_outlined,
                        title: l10n.billingGuideTitle,
                        subtitle: l10n.billingGuideSubtitle,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BillingGuidePage(),
                          ),
                        ),
                      ),
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.cloud_outlined,
                        title: l10n.rancountSelfHostGuide,
                        subtitle: l10n.rancountSelfHostGuideDesc,
                        onTap: () =>
                            _openLink(context, RanCountLinks.selfHostGuide),
                      ),
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.feedback_outlined,
                        title: l10n.mineFeedback,
                        subtitle: l10n.mineFeedbackSubtitle,
                        onTap: () => _openLink(context, RanCountLinks.feedback),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      showToast(context, AppLocalizations.of(context).settingsOpenLinkFailed);
    }
  }
}
