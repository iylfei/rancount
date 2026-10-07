import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/services/update/update_checker.dart';
import 'package:beecount/services/update/update_asset_name.dart';

void main() {
  test('server releases choose a universal APK over ABI-specific APKs', () {
    final assets = [
      {'name': 'rancount-0.0.2-armeabi-v7a.apk', 'url': '/armv7'},
      {'name': 'rancount-0.0.2-universal.apk', 'url': '/universal'},
      {'name': 'rancount-0.0.2.apk', 'url': '/arm64'},
    ];
    expect(UpdateChecker.pickApk(assets, '0.0.2')?['url'], '/universal');
    expect(UpdateChecker.pickApk([assets.first], '0.0.2'), isNull);
  });

  test('version comparison uses numeric version components', () {
    expect(UpdateChecker.isNewerVersion('0.0.2', '0.0.1'), isTrue);
    expect(UpdateChecker.isNewerVersion('0.0.2', '0.0.2'), isFalse);
    expect(UpdateChecker.isNewerVersion('0.0.2', '0.0.10'), isFalse);
  });

  test('server APK names retain their version in the local download name', () {
    expect(
      UpdateAssetName.versionFromUrl(
        'https://count.iylnet.xyz/api/v1/app-updates/files/rancount-0.1.5-universal.apk',
      ),
      '0.1.5',
    );
    expect(
      UpdateAssetName.versionFromUrl('https://example.com/beecount-0.8.1.apk'),
      '0.8.1',
    );
  });
}
