import 'dart:io';

import 'package:flutter/services.dart';

/// Android share intents create a local draft. No transaction is saved here.
class ImageShareHandlerService {
  static const _channel = MethodChannel('com.tntlikely.beecount/share');
  final Future<void> Function(String imagePath) onImageShared;

  ImageShareHandlerService({required this.onImageShared}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onImageShared' || !Platform.isAndroid) return;
      await consumePendingShare();
    });
    consumePendingShare();
  }

  Future<void> consumePendingShare() async {
    final path = await _channel.invokeMethod<String>('consumePendingShare');
    if (path != null && path.isNotEmpty) await onImageShared(path);
  }
}
