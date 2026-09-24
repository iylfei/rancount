import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Only app-cache copies belong to billing; source gallery files are never owned.
class ImageBillingCache {
  final Directory cache;
  ImageBillingCache(this.cache);
  Directory get directory => Directory(p.join(cache.path, 'rancount_picker'));
  File get _journal => File(p.join(directory.path, 'picker.json'));
  static bool _picking = false;
  static final _uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false);

  Future<Set<String>> _pluginFiles() async {
    final files = <String>{};
    await for (final entry in cache.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (!_uuid.hasMatch(name)) continue;
      if (entry is File &&
          RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false).hasMatch(name)) {
        files.add(p.normalize(entry.path));
      } else if (entry is Directory && name.length == 36) {
        await for (final file in entry.list(followLinks: false)) {
          if (file is File) files.add(p.normalize(file.path));
        }
      }
    }
    return files;
  }

  Future<void> beginPick() async {
    await directory.create(recursive: true);
    await _journal.writeAsString(jsonEncode((await _pluginFiles()).toList()),
        flush: true);
  }

  Future<void> finishPick() async {
    if (!await _journal.exists()) return;
    final previous = (jsonDecode(await _journal.readAsString()) as List)
        .cast<String>()
        .toSet();
    for (final path in (await _pluginFiles()).difference(previous)) {
      await File(path).delete();
    }
    await _journal.delete();
  }

  Future<File> stage(File source) async {
    await directory.create(recursive: true);
    return source.copy(p.join(directory.path, '${const Uuid().v4()}.image'));
  }

  Future<void> cleanStale() async {
    await finishPick();
    if (!await directory.exists()) return;
    await for (final file in directory.list(followLinks: false)) {
      if (file is File) await file.delete();
    }
  }

  static Future<File?> pick(ImageSource source) async {
    if (_picking) return null;
    _picking = true;
    ImageBillingCache? owner;
    try {
      owner = ImageBillingCache(await getTemporaryDirectory());
      await owner.beginPick();
      // No plugin resize: otherwise it creates an additional untracked original.
      final selected = await ImagePicker().pickImage(source: source);
      if (selected == null) return null;
      final staged = await owner.stage(File(selected.path));
      try {
        final compressed = await FlutterImageCompress.compressAndGetFile(
            staged.path,
            p.join(owner.directory.path, '${const Uuid().v4()}.jpg'),
            minWidth: 1920,
            minHeight: 1920,
            quality: 85,
            keepExif: false);
        if (compressed == null) return staged;
        await staged.delete();
        return File(compressed.path);
      } catch (_) {
        // Recognition can still consume the owned original if compression fails.
        return staged;
      }
    } finally {
      try {
        await owner?.finishPick();
      } finally {
        _picking = false;
      }
    }
  }
}
