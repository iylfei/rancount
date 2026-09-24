import 'dart:io';
import 'package:beecount/services/billing/image_billing_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
      'cleanup removes interrupted picker copies but preserves preexisting cache and source',
      () async {
    final root = await Directory.systemTemp.createTemp('rancount-cache-test');
    try {
      final cache = await Directory(p.join(root.path, 'cache')).create();
      final source = await File(p.join(root.path, 'gallery.jpg'))
          .writeAsString('original');
      const first = '00000000-0000-4000-8000-000000000001';
      const second = '00000000-0000-4000-8000-000000000002';
      final old =
          await File(p.join(cache.path, '$first.jpg')).writeAsString('older');
      final owner = ImageBillingCache(cache);
      await owner.beginPick();
      final folder = await Directory(p.join(cache.path, second)).create();
      final copy = await source.copy(p.join(folder.path, 'picked.jpg'));
      final staged = await owner.stage(copy);
      await ImageBillingCache(cache).cleanStale();
      expect(await source.readAsString(), 'original');
      expect(await old.exists(), isTrue);
      expect(await copy.exists(), isFalse);
      expect(await staged.exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
