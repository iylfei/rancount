import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/billing/image_vision_config.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';

class ImageVisionSettingsSection extends StatefulWidget {
  const ImageVisionSettingsSection({super.key});

  @override
  State<ImageVisionSettingsSection> createState() =>
      _ImageVisionSettingsSectionState();
}

class _ImageVisionSettingsSectionState
    extends State<ImageVisionSettingsSection> {
  final _store = const ImageVisionConfigStore();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  String _savedKey = '';
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final config = await _store.load();
      if (!mounted) return;
      _baseUrl.text = config.baseUrl;
      _model.text = config.model;
      _savedKey = config.apiKey;
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_loading || _loadFailed || _saving) return;
    final l10n = AppLocalizations.of(context);
    final config = ImageVisionConfig(
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      apiKey: _apiKey.text.trim().isEmpty ? _savedKey : _apiKey.text.trim(),
    );
    final uri = Uri.tryParse(config.baseUrl);
    if (!config.isComplete ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      showToast(context, l10n.imageVisionConfigInvalid);
      return;
    }
    setState(() => _saving = true);
    try {
      await _store.save(config);
      if (!mounted) return;
      _savedKey = config.apiKey;
      _apiKey.clear();
      showToast(context, l10n.imageVisionConfigSaved);
    } catch (_) {
      if (mounted) showToast(context, l10n.imageVisionConfigSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.imageVisionSettingsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.imageVisionSettingsDescription),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_loadFailed) ...[
              Text(l10n.imageVisionConfigLoadFailed),
              TextButton(onPressed: _load, child: Text(l10n.helpCenterRetry)),
            ] else ...[
              TextField(
                controller: _baseUrl,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.imageVisionBaseUrl,
                  hintText: 'https://example.com/v1',
                ),
              ),
              TextField(
                controller: _model,
                enabled: !_saving,
                autocorrect: false,
                decoration: InputDecoration(labelText: l10n.aiVisionModelTitle),
              ),
              TextField(
                controller: _apiKey,
                enabled: !_saving,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: _savedKey.isEmpty ? null : l10n.imageVisionKeepKey,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.imageVisionLocalPrivacy),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.commonSave),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
