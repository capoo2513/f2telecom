import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// 실사 임시저장 1건
class SurveyDraft {
  final String station;
  final String floor;
  final String templateId;
  final Map<String, int> counts;
  final Map<String, String> values;
  final Map<String, List<String>> photos;
  final DateTime savedAt;

  SurveyDraft({
    required this.station,
    required this.floor,
    required this.templateId,
    required this.counts,
    required this.values,
    required this.photos,
    required this.savedAt,
  });

  /// 같은 국소 + 같은 분류 = 같은 임시저장
  String get id => SurveyDraftStore.makeId(station, templateId);

  int get photoCount => photos.values.fold(0, (a, l) => a + l.length);

  Map<String, dynamic> toJson() => {
        'station': station,
        'floor': floor,
        'templateId': templateId,
        'counts': counts,
        'values': values,
        'photos': photos,
        'savedAt': savedAt.toIso8601String(),
      };

  static SurveyDraft fromJson(Map<String, dynamic> j) {
    final photos = <String, List<String>>{};
    (j['photos'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      // 휴대폰에서 지워진 사진은 빼고 불러오기
      final list = (v as List).map((e) => e.toString()).where((p) => File(p).existsSync()).toList();
      if (list.isNotEmpty) photos[k] = list;
    });
    return SurveyDraft(
      station: j['station'] ?? '',
      floor: j['floor'] ?? '',
      templateId: j['templateId'] ?? '',
      counts: (j['counts'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toInt())),
      values: (j['values'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      photos: photos,
      savedAt: DateTime.tryParse(j['savedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

/// 휴대폰 안(SharedPreferences)에 임시저장 목록 보관
class SurveyDraftStore {
  static const _key = 'survey_drafts_v1';

  static String makeId(String station, String templateId) =>
      '${station.trim()}|$templateId';

  static Future<List<SurveyDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = list
          .map((e) => SurveyDraft.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeAll(List<SurveyDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<SurveyDraft?> find(String station, String templateId) async {
    final id = makeId(station, templateId);
    for (final d in await loadAll()) {
      if (d.id == id) return d;
    }
    return null;
  }

  static Future<void> save(SurveyDraft draft) async {
    final all = await loadAll();
    all.removeWhere((d) => d.id == draft.id);
    all.insert(0, draft);
    await _writeAll(all);
  }

  static Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((d) => d.id == id);
    await _writeAll(all);
  }
}
