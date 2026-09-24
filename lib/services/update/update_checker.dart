import 'package:dio/dio.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../system/logger_service.dart';
import 'update_result.dart';

/// Checks the release feed of the BeeCount Cloud server configured on this device.
class UpdateChecker {
  UpdateChecker._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static Future<UpdateResult> checkUpdate() async {
    try {
      final config = await CloudServiceStore().loadBeeCountCloud();
      final baseUrl = config?.beecountCloudBaseUrl?.trim();
      final origin = baseUrl == null ? null : Uri.tryParse(baseUrl);
      if (origin == null ||
          !origin.hasAuthority ||
          (origin.scheme != 'https' &&
              !(origin.scheme == 'http' &&
                  (origin.host == 'localhost' || origin.host == '127.0.0.1')))) {
        return UpdateResult(
          message: '__UPDATE_SERVER_NOT_CONFIGURED__',
        );
      }
      final prefix = (config?.beecountCloudApiPrefix ?? '/api/v1')
          .replaceFirst(RegExp(r'/+$'), '');
      final feed = origin.resolve(
          '${prefix.startsWith('/') ? prefix : '/$prefix'}/app-updates/latest');
      final response = await _dio.getUri(feed);
      if (response.statusCode == 204) {
        return UpdateResult(message: '__UPDATE_NO_APK_FOUND__');
      }
      final data = response.data;
      if (data is! Map) throw const FormatException('更新清单格式不正确');
      final version = data['version'];
      if (version is! String || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
        throw const FormatException('更新版本号无效');
      }
      final current = (await PackageInfo.fromPlatform()).version;
      if (!isNewerVersion(version, current)) {
        return UpdateResult(message: '__UPDATE_ALREADY_LATEST_SIMPLE__');
      }
      final assets = data['assets'];
      if (assets is! List) throw const FormatException('更新文件清单无效');
      final asset = pickApk(assets.cast<dynamic>(), version);
      if (asset == null) return UpdateResult(message: '__UPDATE_NO_APK_FOUND__');
      final url = asset['url'];
      final checksum = asset['sha256'];
      if (url is! String ||
          checksum is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(checksum)) {
        throw const FormatException('更新文件信息无效');
      }
      final downloadUri = origin.resolve(url);
      if (downloadUri.scheme != origin.scheme ||
          downloadUri.host != origin.host ||
          downloadUri.port != origin.port) {
        throw const FormatException('更新文件地址与云服务器不一致');
      }
      return UpdateResult(
        hasUpdate: true,
        version: version,
        downloadUrl: downloadUri.toString(),
        sha256: checksum.toLowerCase(),
        releaseNotes: data['release_notes'] is String
            ? data['release_notes'] as String
            : '',
      );
    } catch (error) {
      logger.error('UpdateChecker', '检查云服务器更新失败', error);
      return UpdateResult(message: '__UPDATE_CHECK_EXCEPTION__:$error');
    }
  }

  /// Prefer a universal build; otherwise use the release's main APK.
  static Map? pickApk(List<dynamic> assets, String version) {
    final apks = assets.whereType<Map>().where((asset) {
      final name = asset['name'];
      return name is String && name.toLowerCase().endsWith('.apk');
    }).toList();
    for (final suffix in ['-universal.apk', '$version.apk']) {
      for (final apk in apks) {
        if ((apk['name'] as String).endsWith(suffix)) return apk;
      }
    }
    return null;
  }

  static bool isNewerVersion(String candidate, String current) {
    final a = candidate.split('.').map(int.parse).toList();
    final currentCore = current.split('-').first.split('+').first;
    final b = currentCore.split('.').map(int.tryParse).toList();
    if (b.any((part) => part == null)) return false;
    for (var i = 0; i < 3; i++) {
      final oldPart = i < b.length ? b[i]! : 0;
      if (a[i] != oldPart) return a[i] > oldPart;
    }
    return false;
  }
}
