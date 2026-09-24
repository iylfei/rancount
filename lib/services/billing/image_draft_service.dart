import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../ai/core/ai_extraction_context.dart';
import '../../ai/core/bill_info.dart';
import '../../ai/core/json_response_parser.dart';
import '../../ai/core/prompt_builder.dart';
import '../../ai/providers/ai_provider_factory.dart';
import '../../ai/providers/ai_provider_config.dart';
import '../../data/repositories/base_repository.dart';
import 'image_vision_config.dart';

class ImageDraftEntry {
  final String id;
  final BillInfo bill;
  final bool selected;
  final bool saved;

  const ImageDraftEntry({
    required this.id,
    required this.bill,
    this.selected = true,
    this.saved = false,
  });

  ImageDraftEntry copyWith({BillInfo? bill, bool? selected, bool? saved}) =>
      ImageDraftEntry(
        id: id,
        bill: bill ?? this.bill,
        selected: selected ?? this.selected,
        saved: saved ?? this.saved,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bill': bill.toJson(),
        'selected': selected,
        'saved': saved,
      };

  factory ImageDraftEntry.fromJson(Map<String, dynamic> json) =>
      ImageDraftEntry(
        id: json['id'] as String,
        bill: BillInfo.fromJson(Map<String, dynamic>.from(json['bill'] as Map)),
        selected: json['selected'] != false,
        saved: json['saved'] == true,
      );
}

class ImageDraftSession {
  final String id;
  final int ledgerId;
  final DateTime createdAt;
  final List<ImageDraftEntry> entries;

  const ImageDraftSession({
    required this.id,
    required this.ledgerId,
    required this.createdAt,
    required this.entries,
  });

  ImageDraftSession copyWith({List<ImageDraftEntry>? entries}) =>
      ImageDraftSession(
        id: id,
        ledgerId: ledgerId,
        createdAt: createdAt,
        entries: entries ?? this.entries,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ledgerId': ledgerId,
        'createdAt': createdAt.toIso8601String(),
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory ImageDraftSession.fromJson(Map<String, dynamic> json) =>
      ImageDraftSession(
        id: json['id'] as String,
        ledgerId: json['ledgerId'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        entries: (json['entries'] as List)
            .map((item) => ImageDraftEntry.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

/// Drafts stay on this device; screenshots and model responses are never saved here.
class ImageDraftStore {
  static const _key = 'rancount_image_drafts_v1';
  static Future<void> _pendingWrite = Future.value();

  Future<void> _serialized(Future<void> Function() operation) {
    final result = _pendingWrite.then((_) => operation());
    _pendingWrite = result.catchError((Object _) {});
    return result;
  }

  final Future<SharedPreferences> Function() _preferences;

  ImageDraftStore({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  Future<List<ImageDraftSession>> load() async {
    final prefs = await _preferences();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((item) => ImageDraftSession.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      throw const FormatException('草稿数据无法读取，已保留原数据');
    }
  }

  Future<void> put(ImageDraftSession session) => _serialized(() async {
        final sessions = await load();
        sessions.removeWhere((item) => item.id == session.id);
        sessions.insert(0, session);
        final prefs = await _preferences();
        final saved = await prefs.setString(
            _key, jsonEncode(sessions.map((s) => s.toJson()).toList()));
        if (!saved) throw StateError('草稿暂存失败');
      });

  Future<void> remove(String id) => _serialized(() async {
        final sessions = await load();
        sessions.removeWhere((item) => item.id == id);
        final prefs = await _preferences();
        final saved = await prefs.setString(
            _key, jsonEncode(sessions.map((s) => s.toJson()).toList()));
        if (!saved) throw StateError('草稿暂存失败');
      });
}

class ImageDraftService {
  final BaseRepository repository;
  final ImageDraftStore store;
  final JsonResponseParser parser;

  const ImageDraftService({
    required this.repository,
    required this.store,
    this.parser = const JsonResponseParser(),
  });

  Future<ImageDraftSession> recognize(File image, int ledgerId) async {
    final context = await AiExtractionContext.forLedger(
      repository: repository,
      ledgerId: ledgerId,
    );
    final prompt = const PromptBuilder().build(
      context: context,
      inputSource: '分析支付页面截图，从中',
      billGuard: PromptBuilder.billGuardForImage,
      templateOverride: PromptBuilder.draftImageTemplate,
    );
    final config = await const ImageVisionConfigStore().load();
    if (!config.isComplete) throw StateError('image-vision-not-configured');
    final response = await AIProviderFactory.visionWithConfig(
      image,
      prompt,
      AIServiceProviderConfig(
        id: 'rancount_image_vision',
        name: 'RanCount Image Vision',
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        visionModel: config.model,
        createdAt: DateTime(2026, 9, 23),
      ),
    );
    final bills = parser.parseDraft(response);
    final uuid = const Uuid();
    final session = ImageDraftSession(
      id: uuid.v4(),
      ledgerId: ledgerId,
      createdAt: DateTime.now(),
      entries: bills
          .map((bill) => ImageDraftEntry(id: uuid.v4(), bill: bill))
          .toList(),
    );
    if (session.entries.isNotEmpty) await store.put(session);
    return session;
  }
}
