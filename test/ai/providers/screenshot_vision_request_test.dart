import 'dart:convert';
import 'dart:io';

import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;
  test('official Flash screenshot recognition disables thinking', () {
    for (final model in [
      'deepseek-flash',
      'deepseek-v4-flash',
      'deepseek-v4-flash-vision-exp',
    ]) {
      expect(
        AIProviderFactory.screenshotVisionOptions(
            'https://api.deepseek.com/v1', model),
        {
          'thinking': {'type': 'disabled'}
        },
      );
    }
  });

  test('other providers and unknown models keep their existing parameters', () {
    for (final endpoint in [
      'https://gateway.example/v1',
      'https://api.deepseek.com.example/v1',
      'https://example.com/api.deepseek.com',
    ]) {
      expect(
          AIProviderFactory.screenshotVisionOptions(endpoint, 'deepseek-flash'),
          isEmpty);
    }
    expect(
      AIProviderFactory.screenshotVisionOptions(
          'https://api.deepseek.com', 'unknown-model'),
      isEmpty,
    );
  });

  test('compatible endpoint still receives original image and parses bills',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final directory = await Directory.systemTemp.createTemp('vision-request-');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==');
    final image = await File('${directory.path}/bill.png').writeAsBytes(bytes);
    final received = server.first.then((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': '[{"amount":12,"type":"expense"}]'}
          }
        ]
      }));
      await request.response.close();
      return body;
    });
    final result = await AIProviderFactory.visionWithConfig(
      image,
      'Extract bills',
      AIServiceProviderConfig(
        id: 'test',
        name: 'test',
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        visionModel: 'deepseek-flash',
        createdAt: DateTime(2026),
      ),
    );
    final body = await received;
    expect(body.containsKey('thinking'), isFalse);
    expect(body['messages'][0]['content'][1]['image_url']['url'],
        'data:image/png;base64,${base64Encode(bytes)}');
    expect(jsonDecode(result)[0]['amount'], 12);
  });
}
