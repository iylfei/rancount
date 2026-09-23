import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local screenshot vision configuration. None of these values enters
/// SharedPreferences or the BeeCount Cloud AI profile snapshot.
class ImageVisionConfig {
  final String baseUrl;
  final String model;
  final String apiKey;

  const ImageVisionConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  bool get isComplete =>
      baseUrl.isNotEmpty && model.isNotEmpty && apiKey.isNotEmpty;
}

class ImageVisionConfigStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _urlKey = 'rancount_image_vision_url';
  static const _modelKey = 'rancount_image_vision_model';
  static const _apiKey = 'rancount_image_vision_api_key';

  const ImageVisionConfigStore();

  Future<ImageVisionConfig> load() async => ImageVisionConfig(
        baseUrl: (await _storage.read(key: _urlKey) ?? '').trim(),
        model: (await _storage.read(key: _modelKey) ?? '').trim(),
        apiKey: (await _storage.read(key: _apiKey) ?? '').trim(),
      );

  Future<void> save(ImageVisionConfig config) async {
    await _storage.write(key: _urlKey, value: config.baseUrl.trim());
    await _storage.write(key: _modelKey, value: config.model.trim());
    await _storage.write(key: _apiKey, value: config.apiKey.trim());
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _modelKey);
    await _storage.delete(key: _apiKey);
  }
}
