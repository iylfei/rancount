import 'package:beecount/providers/appearance_providers.dart';
import 'package:beecount/services/export/config_export_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Android defaults to liquid glass; other platforms retain classic', () {
    final android = AppAppearanceSettings.defaults(isAndroid: true);
    final other = AppAppearanceSettings.defaults(isAndroid: false);
    expect(android.visualStyle, AppVisualStyle.liquidGlass);
    expect(other.visualStyle, AppVisualStyle.classic);
    expect(android.glassQuality, GlassQuality.automatic);
    expect(android.interfaceAnimations, isTrue);
    expect(android.hapticsEnabled, isTrue);
  });

  test('missing and invalid stored values use platform defaults', () async {
    SharedPreferences.setMockInitialValues({
      'visualStyle': 'future-style',
      'glassQuality': 12,
      'interfaceAnimations': 'false',
    });
    final preferences = await SharedPreferences.getInstance();
    final settings =
        AppAppearanceSettings.fromPreferences(preferences, isAndroid: true);
    expect(settings.visualStyle, AppVisualStyle.liquidGlass);
    expect(settings.glassQuality, GlassQuality.automatic);
    expect(settings.interfaceAnimations, isTrue);
    expect(settings.hapticsEnabled, isTrue);
  });

  test('saved classic and disabled feedback survive initialization', () async {
    SharedPreferences.setMockInitialValues({
      'visualStyle': 'classic',
      'glassQuality': 'simplified',
      'interfaceAnimations': false,
      'hapticsEnabled': false,
      'primaryColor': 0xFFFFC107,
      'headerSkin': 'original-skin',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appearanceInitProvider.future);
    expect(container.read(visualStyleProvider), AppVisualStyle.classic);
    expect(container.read(glassQualityProvider), GlassQuality.simplified);
    expect(container.read(interfaceAnimationsProvider), isFalse);
    expect(container.read(hapticsEnabledProvider), isFalse);

    container.read(visualStyleProvider.notifier).state =
        AppVisualStyle.liquidGlass;
    container.read(glassQualityProvider.notifier).state =
        GlassQuality.automatic;
    container.read(interfaceAnimationsProvider.notifier).state = true;
    container.read(hapticsEnabledProvider.notifier).state = true;
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('visualStyle'), 'liquidGlass');
    expect(preferences.getString('glassQuality'), 'automatic');
    expect(preferences.getBool('interfaceAnimations'), isTrue);
    expect(preferences.getBool('hapticsEnabled'), isTrue);
    expect(preferences.getInt('primaryColor'), 0xFFFFC107);
    expect(preferences.getString('headerSkin'), 'original-skin');
  });

  test('a separate container restores the same saved appearance', () async {
    SharedPreferences.setMockInitialValues({
      'visualStyle': 'liquidGlass',
      'glassQuality': 'simplified',
      'interfaceAnimations': false,
      'hapticsEnabled': false,
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    restoreAppearanceSettings(container.read, preferences);
    expect(container.read(visualStyleProvider), AppVisualStyle.liquidGlass);
    expect(container.read(glassQualityProvider), GlassQuality.simplified);
    expect(container.read(interfaceAnimationsProvider), isFalse);
    expect(container.read(hapticsEnabledProvider), isFalse);
  });

  test('appearance fields are optional in old configuration maps', () {
    final config = AppSettingsConfig.fromMap({'theme_mode': 'dark'});
    expect(config.visualStyle, isNull);
    expect(config.glassQuality, isNull);
    expect(config.interfaceAnimations, isNull);
    expect(config.hapticsEnabled, isNull);
    expect(config.toMap(), {'theme_mode': 'dark'});
  });

  test('invalid imported enum values are ignored', () {
    final config = AppSettingsConfig.fromMap({
      'visual_style': 'future-style',
      'glass_quality': false,
      'interface_animations': 'false',
      'haptics_enabled': 0,
    });
    expect(config.toMap(), isEmpty);
  });

  test('YAML export and import preserve all four appearance fields', () async {
    SharedPreferences.setMockInitialValues({
      'visualStyle': 'liquidGlass',
      'glassQuality': 'simplified',
      'interfaceAnimations': false,
      'hapticsEnabled': false,
    });
    const options = ExportOptions(ai: false);
    final yaml = await ConfigExportService.exportToYaml(options: options);
    final document = loadYaml(yaml) as YamlMap;
    final appearance = document['app_settings'] as YamlMap;
    expect(appearance['visual_style'], 'liquidGlass');
    expect(appearance['glass_quality'], 'simplified');
    expect(appearance['interface_animations'], isFalse);
    expect(appearance['haptics_enabled'], isFalse);

    SharedPreferences.setMockInitialValues({});
    await ConfigExportService.importFromYaml(yaml, options: options);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('visualStyle'), 'liquidGlass');
    expect(preferences.getString('glassQuality'), 'simplified');
    expect(preferences.getBool('interfaceAnimations'), isFalse);
    expect(preferences.getBool('hapticsEnabled'), isFalse);
  });

  test('importing old YAML keeps the existing appearance values', () async {
    SharedPreferences.setMockInitialValues({
      'visualStyle': 'classic',
      'glassQuality': 'simplified',
      'interfaceAnimations': false,
      'hapticsEnabled': false,
    });
    await ConfigExportService.importFromYaml(
      'app_settings:\n  theme_mode: dark\n',
      options: const ExportOptions(ai: false),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('themeMode'), 'dark');
    expect(preferences.getString('visualStyle'), 'classic');
    expect(preferences.getString('glassQuality'), 'simplified');
    expect(preferences.getBool('interfaceAnimations'), isFalse);
    expect(preferences.getBool('hapticsEnabled'), isFalse);
  });
}
