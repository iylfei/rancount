import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/billing/image_draft_service.dart';
import '../../l10n/app_localizations.dart';
import '../ai/ai_settings_page.dart';
import 'image_draft_page.dart';
import 'ios_auto_billing_page.dart';

class AutoBillingSettingsPage extends StatelessWidget {
  const AutoBillingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Platform.isIOS
      ? const IOSAutoBillingPage()
      : const AndroidAutoBillingPage();
}

class AndroidAutoBillingPage extends StatefulWidget {
  const AndroidAutoBillingPage({super.key});

  @override
  State<AndroidAutoBillingPage> createState() => _AndroidAutoBillingPageState();
}

class _AndroidAutoBillingPageState extends State<AndroidAutoBillingPage>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.tntlikely.beecount/capture');
  final _store = ImageDraftStore();
  late Future<List<ImageDraftSession>> _sessions = _store.load();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _sessions = _store.load());
    }
  }

  String _label(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _addTile() async {
    try {
      final added =
          await _channel.invokeMethod<bool>('requestAddTile') ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? _label('已添加截图记账按钮', 'Screenshot billing tile added')
                : _label(
                    '请在快捷设置的编辑页面手动添加「截图记账」按钮',
                    'Open Quick Settings edit and add the screenshot billing tile',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _label('请在快捷设置中手动添加按钮', 'Add the tile manually in Quick Settings'),
          ),
        ),
      );
    }
  }

  Future<void> _open(ImageDraftSession session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImageDraftPage(existing: session)),
    );
    if (mounted) setState(() => _sessions = _store.load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_label('截图记账', 'Screenshot billing'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: Text(AppLocalizations.of(context).aiSettingsTitle),
            subtitle: Text(
              AppLocalizations.of(context).imageVisionSettingsTitle,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AISettingsPage())),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label('从快捷设置主动截屏', 'Capture from Quick Settings'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  _label(
                    '1. 将「截图记账」加入快捷设置。\n2. 在支付页面下拉并点击按钮。\n3. 同意系统截屏授权。\n4. 逐笔核对草稿后确认入账。',
                    '1. Add Screenshot billing to Quick Settings.\n2. Open it on the payment page.\n3. Grant one-time screen capture consent.\n4. Review drafts before saving.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _addTile,
                  child: Text(_label('添加快捷设置按钮', 'Add Quick Settings tile')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _label('稍后继续的草稿', 'Saved drafts'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<ImageDraftSession>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('草稿暂时无法读取，原数据已保留，请重启后重试。');
            }
            final sessions = (snapshot.data ?? const <ImageDraftSession>[])
                .where(
                  (session) => session.entries.any((entry) => !entry.saved),
                )
                .toList();
            if (sessions.isEmpty) {
              return Text(_label('暂无草稿', 'No drafts'));
            }
            return Column(
              children: [
                for (final session in sessions)
                  ListTile(
                    title: Text(
                      _label(
                        '${session.entries.where((entry) => !entry.saved).length} 笔待核对',
                        '${session.entries.length} drafts to review',
                      ),
                    ),
                    subtitle: Text(session.createdAt.toLocal().toString()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(session),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
