import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/billing/image_draft_service.dart';
import '../../services/billing/image_vision_config.dart';
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

class _AndroidAutoBillingPageState extends State<AndroidAutoBillingPage> {
  static const _channel = MethodChannel('com.tntlikely.beecount/capture');
  final _store = ImageDraftStore();
  late Future<List<ImageDraftSession>> _sessions = _store.load();
  final _visionStore = const ImageVisionConfigStore();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _hasKey = false;
  bool _savingVision = false;

  @override
  void initState() {
    super.initState();
    _loadVision();
  }

  Future<void> _loadVision() async {
    try {
      final config = await _visionStore.load();
      if (!mounted) return;
      setState(() {
        _baseUrl.text = config.baseUrl;
        _model.text = config.model;
        _hasKey = config.apiKey.isNotEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _hasKey = false);
    }
  }

  Future<void> _saveVision() async {
    if (_savingVision) return;
    final url = _baseUrl.text.trim();
    final model = _model.text.trim();
    final parsed = Uri.tryParse(url);
    ImageVisionConfig old;
    try {
      old = await _visionStore.load();
    } catch (_) {
      old = const ImageVisionConfig(baseUrl: '', model: '', apiKey: '');
    }
    final key = _apiKey.text.trim().isEmpty ? old.apiKey : _apiKey.text.trim();
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        model.isEmpty ||
        key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_label('请填写有效 API 地址、视觉模型和密钥',
              'Enter a valid API URL, vision model and key')),
        ));
      }
      return;
    }
    setState(() => _savingVision = true);
    try {
      await _visionStore
          .save(ImageVisionConfig(baseUrl: url, model: model, apiKey: key));
      _apiKey.clear();
      if (!mounted) return;
      setState(() => _hasKey = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_label(
            '视觉接口配置已保存在本机', 'Vision configuration saved on this device')),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_label('安全存储不可用，配置未保存',
              'Secure storage unavailable; configuration not saved')),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingVision = false);
    }
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  String _label(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _addTile() async {
    try {
      final added =
          await _channel.invokeMethod<bool>('requestAddTile') ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added
              ? _label('已添加截图记账按钮', 'Screenshot billing tile added')
              : _label('请在快捷设置的编辑页面手动添加「截图记账」按钮',
                  'Open Quick Settings edit and add the screenshot billing tile'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            _label('请在快捷设置中手动添加按钮', 'Add the tile manually in Quick Settings')),
      ));
    }
  }

  Future<void> _open(ImageDraftSession session) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImageDraftPage(existing: session),
    ));
    if (mounted) setState(() => _sessions = _store.load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_label('截图记账', 'Screenshot billing'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
              child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_label('截图视觉接口', 'Screenshot vision API'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                        labelText: _label('OpenAI 兼容 API 基础地址',
                            'OpenAI-compatible API base URL'),
                        hintText: 'https://example.com/v1'),
                  ),
                  TextField(
                    controller: _model,
                    decoration: InputDecoration(
                        labelText: _label('视觉模型', 'Vision model')),
                  ),
                  TextField(
                    controller: _apiKey,
                    obscureText: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                        labelText: _label('API 密钥', 'API key'),
                        hintText: _hasKey
                            ? _label(
                                '已保存，留空则保持原密钥', 'Saved; leave blank to keep it')
                            : null),
                  ),
                  const SizedBox(height: 8),
                  Text(_label('密钥仅保存在本机，不随账本同步。图片直接发送到所填接口。',
                      'The key stays on this device. Images go directly to this endpoint.')),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _savingVision ? null : _saveVision,
                      child: Text(_label('保存接口配置', 'Save API configuration'))),
                ]),
          )),
          const SizedBox(height: 16),
          Card(
              child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label('从快捷设置主动截屏', 'Capture from Quick Settings'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(_label(
                '1. 将「截图记账」加入快捷设置。\n2. 在支付页面下拉并点击按钮。\n3. 同意系统截屏授权。\n4. 逐笔核对草稿后确认入账。',
                '1. Add Screenshot billing to Quick Settings.\n2. Open it on the payment page.\n3. Grant one-time screen capture consent.\n4. Review drafts before saving.',
              )),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _addTile,
                  child: Text(_label('添加快捷设置按钮', 'Add Quick Settings tile'))),
            ]),
          )),
          const SizedBox(height: 24),
          Text(_label('稍后继续的草稿', 'Saved drafts'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<ImageDraftSession>>(
            future: _sessions,
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? const <ImageDraftSession>[];
              if (sessions.isEmpty) {
                return Text(_label('暂无草稿', 'No drafts'));
              }
              return Column(children: [
                for (final session in sessions)
                  ListTile(
                    title: Text(_label('${session.entries.length} 笔待核对',
                        '${session.entries.length} drafts to review')),
                    subtitle: Text(session.createdAt.toLocal().toString()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(session),
                  ),
              ]);
            },
          ),
        ]),
      );
}
