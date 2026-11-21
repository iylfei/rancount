import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../providers/smart_billing_providers.dart';
import '../../providers/voice_billing_providers.dart';
import '../ai/ai_settings_page.dart';
import '../automation/auto_billing_settings_page.dart';
import 'billing_guide_page.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/image_billing_helper.dart';

/// 智能记账二级页面
class SmartBillingPage extends ConsumerWidget {
  const SmartBillingPage({super.key});

  /// 语音记账设置区：触发方式 + 自动检测下的静音时长滑块
  Widget _buildVoiceBillingSection(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(voiceBillingSettingsProvider);
    final isAuto = settings.triggerMode == VoiceTriggerMode.auto;

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          AppListTile(
            leading: Icons.mic_none_outlined,
            title: l10n.smartBillingVoiceTrigger,
            subtitle:
                isAuto ? l10n.voiceTriggerModeAuto : l10n.voiceTriggerModeHold,
            onTap: () =>
                _showVoiceTriggerDialog(context, ref, settings.triggerMode),
          ),
          if (isAuto) ...[
            BeeTokens.cardDivider(context),
            const _VoiceSilenceTimeoutSlider(),
          ],
        ],
      ),
    );
  }

  /// 触发方式选择弹窗
  void _showVoiceTriggerDialog(
    BuildContext context,
    WidgetRef ref,
    VoiceTriggerMode current,
  ) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (dialogContext) => BeeAlertDialog(
        title: Text(l10n.smartBillingVoiceTrigger),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in VoiceTriggerMode.values)
              RadioListTile<VoiceTriggerMode>(
                value: mode,
                groupValue: current,
                activeColor: primaryColor,
                title: Text(
                  mode == VoiceTriggerMode.auto
                      ? l10n.voiceTriggerModeAuto
                      : l10n.voiceTriggerModeHold,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  mode == VoiceTriggerMode.auto
                      ? l10n.voiceTriggerModeAutoDesc
                      : l10n.voiceTriggerModeHoldDesc,
                  style: const TextStyle(fontSize: 12),
                ),
                onChanged: (value) async {
                  if (value == null) return;
                  Navigator.pop(dialogContext);
                  await ref
                      .read(voiceBillingSettingsProvider.notifier)
                      .setTriggerMode(value);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.smartBillingPageTitle,
            subtitle: l10n.smartBillingPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // AI设置卡片
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      // AI智能识别设置
                      AppListTile(
                        leading: Icons.psychology_outlined,
                        title: l10n.aiSettingsTitle,
                        subtitle: l10n.aiSettingsSubtitle,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AISettingsPage()),
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
                        leading: Icons.auto_fix_high,
                        title: Platform.isAndroid
                            ? l10n.billingGuideScreenshotTitle
                            : l10n.autoScreenshotBillingIosTitle,
                        subtitle: Platform.isAndroid
                            ? l10n.billingGuideScreenshotSettingsDesc
                            : l10n.autoScreenshotBillingIosDesc,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AutoBillingSettingsPage(),
                          ),
                        ),
                      ),
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.add_photo_alternate_outlined,
                        title: Localizations.localeOf(context).languageCode ==
                                'zh'
                            ? '上传截图识别记账'
                            : 'Upload screenshot to bill',
                        subtitle:
                            Localizations.localeOf(context).languageCode ==
                                    'zh'
                                ? '从相册选择截图识别账单（适用银行等防截屏应用）'
                                : 'Pick a screenshot from gallery (works for banking apps)',
                        onTap: () =>
                            ImageBillingHelper.pickImageForBilling(context, ref),
                      ),
                      BeeTokens.cardDivider(context),
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 智能记账通用设置
                SectionCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      // 自动关联标签
                      AppListTile(
                        leading: Icons.label_outline,
                        title: l10n.smartBillingAutoTags,
                        subtitle: l10n.smartBillingAutoTagsDesc,
                        trailing: Switch.adaptive(
                          value: ref.watch(smartBillingAutoTagsProvider),
                          activeColor: Colors.white,
                          activeTrackColor: Theme.of(context).colorScheme.primary,
                          onChanged: (value) {
                            ref
                                .read(smartBillingAutoTagsProvider.notifier)
                                .state = value;
                          },
                        ),
                      ),
                      if (!Platform.isAndroid) ...[
                        BeeTokens.cardDivider(context),
                        // 自动添加附件
                        AppListTile(
                          leading: Icons.attachment_outlined,
                          title: l10n.smartBillingAutoAttachment,
                          subtitle: l10n.smartBillingAutoAttachmentDesc,
                          trailing: Switch.adaptive(
                            value: ref.watch(
                              smartBillingAutoAttachmentProvider,
                            ),
                            activeColor: Colors.white,
                            activeTrackColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            onChanged: (value) {
                              ref
                                      .read(
                                        smartBillingAutoAttachmentProvider
                                            .notifier,
                                      )
                                      .state =
                                  value;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 语音记账设置（触发方式 + 静音灵敏度）
                _buildVoiceBillingSection(context, ref),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 静音判定时长滑块：拖动时仅更新本地预览，松手后持久化并触发云同步
class _VoiceSilenceTimeoutSlider extends ConsumerStatefulWidget {
  const _VoiceSilenceTimeoutSlider();

  @override
  ConsumerState<_VoiceSilenceTimeoutSlider> createState() =>
      _VoiceSilenceTimeoutSliderState();
}

class _VoiceSilenceTimeoutSliderState
    extends ConsumerState<_VoiceSilenceTimeoutSlider> {
  int? _dragValueMs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(voiceBillingSettingsProvider);
    final displayMs = _dragValueMs ?? settings.silenceTimeoutMs;
    final seconds = (displayMs / 1000).toStringAsFixed(1);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.smartBillingVoiceSilenceTimeout,
                        style: const TextStyle(fontSize: 15)),
                    Text(
                      l10n.smartBillingVoiceSilenceTimeoutValue(seconds),
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Slider.adaptive(
          value: displayMs.toDouble(),
          min: VoiceBillingSettings.minSilenceTimeoutMs.toDouble(),
          max: VoiceBillingSettings.maxSilenceTimeoutMs.toDouble(),
          divisions: (VoiceBillingSettings.maxSilenceTimeoutMs -
                  VoiceBillingSettings.minSilenceTimeoutMs) ~/
              100,
          activeColor: Theme.of(context).colorScheme.primary,
          label: '${seconds}s',
          onChanged: (value) {
            setState(() => _dragValueMs = value.round());
          },
          onChangeEnd: (value) async {
            setState(() => _dragValueMs = null);
            await ref
                .read(voiceBillingSettingsProvider.notifier)
                .setSilenceTimeoutMs(value.round());
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
