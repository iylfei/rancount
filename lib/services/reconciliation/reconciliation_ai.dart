import 'dart:io';

import '../../ai/providers/ai_provider_config.dart';
import '../../ai/providers/ai_provider_factory.dart';
import '../billing/image_vision_config.dart';

/// Screenshot recognition and reconciliation share the device-local model.
class ReconciliationAi {
  const ReconciliationAi();

  Future<AIServiceProviderConfig> _config() async {
    final c = await const ImageVisionConfigStore().load();
    if (!c.isComplete) throw StateError('请先在截图记账设置中配置 AI 服务');
    return AIServiceProviderConfig(
      id: 'reconciliation',
      name: '对账 AI',
      apiKey: c.apiKey,
      baseUrl: c.baseUrl,
      textModel: c.model,
      visionModel: c.model,
      createdAt: DateTime(2026, 10, 9),
    );
  }

  Future<String> chat(String prompt) async => AIProviderFactory.chatWithConfig(
    prompt,
    await _config(),
    systemPrompt: '你是账目核对助手。返回严格 JSON。没有证据时明确列出问题，不编造交易。',
  );

  Future<String> vision(File image, String prompt) async =>
      AIProviderFactory.visionWithConfig(image, prompt, await _config());
}
