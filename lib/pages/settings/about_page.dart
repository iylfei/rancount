import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:beecount/widgets/biz/bee_icon.dart';

import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../services/system/update_service.dart';
import '../../services/system/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/rancount_links.dart';
import 'log_center_page.dart';
import 'privacy_policy_page.dart';

/// 是否为 Google Play 版本（通过 CI 构建时 --dart-define=GOOGLE_PLAY=true 注入）
const _isGooglePlayBuild =
    bool.fromEnvironment('GOOGLE_PLAY', defaultValue: false);

/// 关于页面
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String _versionDisplay = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await _getAppInfo();
    final versionText = info.version.startsWith('dev-')
        ? '${info.version} (${info.buildNumber})'
        : info.version;
    if (!mounted) return;
    setState(() {
      _versionDisplay = versionText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.aboutPageTitle,
            subtitle: l10n.aboutPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16.0.scaled(context, ref),
                  8.0.scaled(context, ref),
                  16.0.scaled(context, ref),
                  16.0.scaled(context, ref),
                ),
                children: [
                  // ===== 顶部:图标 + 应用名 + 版本号(与原版一致)=====
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 24.0.scaled(context, ref),
                    ),
                    child: Column(
                      children: [
                        BeeIcon(
                          color: primary,
                          size: 80.0.scaled(context, ref),
                        ),
                        SizedBox(height: 16.0.scaled(context, ref)),
                        Text(
                          l10n.appName,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                        ),
                        SizedBox(height: 8.0.scaled(context, ref)),
                        Text(
                          _versionDisplay.isEmpty
                              ? l10n.aboutPageLoadingVersion
                              : _versionDisplay,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: BeeTokens.textSecondary(context),
                              ),
                        ),
                      ],
                    ),
                  ),
                  // ===== 功能卡 =====
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // iOS 与 Google Play 版本隐藏检查更新(走应用商店分发)
                        if (!Platform.isIOS && !_isGooglePlayBuild) ...[
                          Consumer(builder: (context, ref2, child) {
                            final isLoading =
                                ref2.watch(checkUpdateLoadingProvider);
                            final downloadProgress =
                                ref2.watch(updateProgressProvider);

                            bool showProgress = false;
                            String title = l10n.mineCheckUpdate;
                            String? subtitle;
                            IconData icon = Icons.system_update_alt_outlined;
                            Widget? trailing;

                            if (isLoading) {
                              title = l10n.mineCheckUpdateDetecting;
                              subtitle = l10n.mineCheckUpdateSubtitleDetecting;
                              icon = Icons.hourglass_empty;
                              trailing = const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2));
                            } else if (downloadProgress.isActive) {
                              showProgress = true;
                              title = l10n.mineUpdateDownloadTitle;
                              icon = Icons.download_outlined;
                              trailing = SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: downloadProgress.progress,
                                  ));
                            }

                            return Column(
                              children: [
                                AppListTile(
                                  leading: icon,
                                  title: title,
                                  subtitle: showProgress
                                      ? downloadProgress.status
                                      : subtitle,
                                  trailing: trailing,
                                  onTap: (isLoading || showProgress)
                                      ? null
                                      : () async {
                                          await UpdateService.checkUpdateWithUI(
                                            context,
                                            setLoading: (loading) => ref2
                                                .read(checkUpdateLoadingProvider
                                                    .notifier)
                                                .state = loading,
                                            setProgress: (progress, status) {
                                              if (status.isEmpty) {
                                                ref2
                                                        .read(
                                                            updateProgressProvider
                                                                .notifier)
                                                        .state =
                                                    UpdateProgress.idle();
                                              } else {
                                                ref2
                                                        .read(
                                                            updateProgressProvider
                                                                .notifier)
                                                        .state =
                                                    UpdateProgress.active(
                                                        progress, status);
                                              }
                                            },
                                          );
                                        },
                                ),
                                BeeTokens.cardDivider(context),
                              ],
                            );
                          }),
                        ],
                        AppListTile(
                          leading: Icons.feedback_outlined,
                          title: l10n.mineFeedback,
                          subtitle: l10n.mineFeedbackSubtitle,
                          onTap: () => _openLink(RanCountLinks.feedback),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.bug_report_outlined,
                          title: l10n.logCenterTitle,
                          subtitle: l10n.logCenterSubtitle,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LogCenterPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppListTile(
                          leading: Icons.code,
                          title: l10n.aboutSourceCode,
                          subtitle: 'iylfei/rancount',
                          onTap: () => _openLink(RanCountLinks.repository),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.history,
                          title: l10n.aboutSourceChanges,
                          onTap: () => _openLink(RanCountLinks.changes),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.privacy_tip_outlined,
                          title: l10n.aboutPrivacyPolicy,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppListTile(
                          leading: Icons.favorite_border,
                          title: l10n.aboutUpstreamTitle,
                          onTap: () => _openLink(RanCountLinks.upstream),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l10n.aboutUpstreamAttribution,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.description_outlined,
                          title: l10n.aboutProjectLicense,
                          onTap: () => _openLink(RanCountLinks.license),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.inventory_2_outlined,
                          title: l10n.aboutDependencyLicenses,
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: l10n.appName,
                            applicationVersion: _versionDisplay,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8.0.scaled(context, ref)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final opened = await _tryOpenUrl(Uri.parse(url));
    if (!opened && mounted) {
      showToast(context, AppLocalizations.of(context).settingsOpenLinkFailed);
    }
  }
}

// -------- 工具方法：关于与更新 --------
class _AppInfo {
  final String version;
  final String buildNumber;
  final String? commit;
  final String? buildTime;
  const _AppInfo(this.version, this.buildNumber, {this.commit, this.buildTime});
}

// 优先读取 CI 注入的 dart-define（CI_VERSION/GIT_COMMIT/BUILD_TIME），否则回退 PackageInfo
Future<_AppInfo> _getAppInfo() async {
  final p = await PackageInfo.fromPlatform();
  final commit = const String.fromEnvironment('GIT_COMMIT');
  final buildTime = const String.fromEnvironment('BUILD_TIME');
  final ciVersion = const String.fromEnvironment('CI_VERSION');

  // 版本号策略：CI版本优先，本地开发显示 "dev-{pubspec版本}"
  final version =
      ciVersion.isNotEmpty ? ciVersion : 'dev-${p.version}'; // 本地开发版本标识

  return _AppInfo(version, p.buildNumber,
      commit: commit.isEmpty ? null : commit,
      buildTime: buildTime.isEmpty ? null : buildTime);
}

/// 尝试使用多种方式打开URL，提供更好的兼容性
Future<bool> _tryOpenUrl(Uri url) async {
  try {
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return true;
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalNonBrowserApplication);
      return true;
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
      return true;
    }
    logger.error('AboutPage', '无法打开URL: $url');
    return false;
  } catch (e) {
    logger.error('AboutPage', '打开URL失败: $url', e);
    return false;
  }
}
