/// Extract the release version from the APK names used by the update feed.
class UpdateAssetName {
  UpdateAssetName._();

  static String? versionFromUrl(String downloadUrl) {
    final fileName = Uri.tryParse(downloadUrl)?.pathSegments.lastOrNull;
    if (fileName == null) return null;
    return RegExp(
      r'^(?:beecount|rancount)-(\d+\.\d+\.\d+)(?:-universal)?\.apk$',
      caseSensitive: false,
    ).firstMatch(fileName)?.group(1);
  }
}
