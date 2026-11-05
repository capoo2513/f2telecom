import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gaetong_model.dart';

// ============================================================
// 개통 임시저장 (휴대폰 안 SharedPreferences) — 실사와 같은 방식
// ============================================================
class GaetongDraft {
  final String station;
  final String tplName; // 예: 5G AAU
  final Map<String, String> values;
  final Map<String, List<String>> photos;
  final DateTime savedAt;

  GaetongDraft({
    required this.station,
    required this.tplName,
    required this.values,
    required this.photos,
    required this.savedAt,
  });

  String get id => GaetongDraftStore.makeId(station, tplName);
  int get photoCount => photos.values.fold(0, (a, l) => a + l.length);

  Map<String, dynamic> toJson() => {
        'station': station,
        'tplName': tplName,
        'values': values,
        'photos': photos,
        'savedAt': savedAt.toIso8601String(),
      };

  static GaetongDraft fromJson(Map<String, dynamic> j) {
    final photos = <String, List<String>>{};
    (j['photos'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final list = (v as List).map((e) => e.toString()).where((p) => File(p).existsSync()).toList();
      if (list.isNotEmpty) photos[k] = list;
    });
    return GaetongDraft(
      station: j['station'] ?? '',
      tplName: j['tplName'] ?? '',
      values: (j['values'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v.toString())),
      photos: photos,
      savedAt: DateTime.tryParse(j['savedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class GaetongDraftStore {
  // 칸 순서가 바뀌면 항목 번호가 달라져 예전 임시저장과 안 맞음 → 버전 올림 (#5: v3)
  static const _key = 'gaetong_drafts_v4';

  static String makeId(String station, String tplName) => '${station.trim()}|$tplName';

  static Future<List<GaetongDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = list.map((e) => GaetongDraft.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeAll(List<GaetongDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<GaetongDraft?> find(String station, String tplName) async {
    final id = makeId(station, tplName);
    for (final d in await loadAll()) {
      if (d.id == id) return d;
    }
    return null;
  }

  static Future<void> save(GaetongDraft draft) async {
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

// ============================================================
// 최근 작성 (밴드에 올리고 완료한 개통, 사진 제외, 최대 30건)
//  → 같은 장비 구성을 국소명만 바꿔서 다시 쓸 때 불러오기
// ============================================================
class GaetongRecentStore {
  static const _key = 'gaetong_recent_v4';
  static const _max = 60;

  /// 완료한 개통(입력 내용 + 사진)을 보관하는 기간 — 지나면 목록과 앱 안 사진을 정리
  static const keepDays = 14;

  static Future<List<GaetongDraft>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final out = list.map((e) => GaetongDraft.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 보관 기간이 남은 것만 (지난 것은 정리)
  static Future<List<GaetongDraft>> loadAll() async {
    final all = await _readAll();
    final limit = DateTime.now().subtract(const Duration(days: keepDays));
    final keep = all.where((d) => d.savedAt.isAfter(limit)).toList();
    final gone = all.where((d) => !d.savedAt.isAfter(limit)).toList();
    if (gone.isNotEmpty) {
      await _writeAll(keep);
      await _deletePhotos(gone, keep);
    }
    return keep;
  }

  static Future<void> _writeAll(List<GaetongDraft> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((d) => d.toJson()).toList()));
  }

  /// 지워지는 기록의 앱 안 사진 파일 정리 (남은 기록·임시저장에서 쓰는 사진은 그대로)
  /// 휴대폰 갤러리(DCIM)에 저장된 사진은 건드리지 않음
  static Future<void> _deletePhotos(List<GaetongDraft> gone, List<GaetongDraft> keep) async {
    try {
      final used = <String>{
        for (final d in keep) ...d.photos.values.expand((l) => l),
        for (final d in await GaetongDraftStore.loadAll()) ...d.photos.values.expand((l) => l),
      };
      for (final d in gone) {
        for (final path in d.photos.values.expand((l) => l)) {
          if (used.contains(path)) continue;
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      }
    } catch (_) {}
  }

  /// 밴드 올리기 완료한 개통 저장 (입력 내용 + 사진 목록)
  static Future<void> add(GaetongDraft d) async {
    final all = await loadAll();
    all.removeWhere((x) => x.id == d.id);
    all.insert(0, d);
    final over = all.length > _max ? all.sublist(_max) : <GaetongDraft>[];
    if (over.isNotEmpty) all.removeRange(_max, all.length);
    await _writeAll(all);
    if (over.isNotEmpty) await _deletePhotos(over, all);
  }

  static Future<void> remove(String id) async {
    final all = await loadAll();
    final gone = all.where((x) => x.id == id).toList();
    all.removeWhere((x) => x.id == id);
    await _writeAll(all);
    await _deletePhotos(gone, all);
  }
}

// ============================================================
// 통합국 시트 ↔ Firebase (CenterData)
//   엑셀(mod_CenterSync)이 E열 중심국명 / F열 국사정보를 올리고,
//   앱은 목록을 받아 검색·자동 불러오기에 쓰고, 새로 입력/수정한 국사정보를 올림
//   (floorBy = 'app' 인 것만 엑셀이 열 때 F열로 가져가서 빨간 글씨로 표시)
// ============================================================
class CenterService {
  /// 내 '개통' 권한 점수 (0 잠금, 1 제한, 2 조회, 3 수정) — 국사정보 수정은 3(수정)만
  static Future<int> myScore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final scores = (doc.data()?['access_scores'] as Map<String, dynamic>?) ?? {};
    return ((scores['material'] ?? 0) as num).toInt();
  }

  static final _col = FirebaseFirestore.instance.collection('CenterData');
  static List<CenterInfo>? _cache;

  static String docId(String name) => name.trim().replaceAll('/', '_');

  static Future<List<CenterInfo>> load({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    final snap = await _col.get();
    final list = snap.docs
        .map((d) => CenterInfo((d.data()['name'] ?? d.id).toString(), (d.data()['floor'] ?? '').toString()))
        .where((c) => c.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _cache = list;
    return list;
  }

  static Future<void> saveFloor(String name, String floor) async {
    await _col.doc(docId(name)).set({
      'name': name.trim(),
      'floor': floor,
      'floorBy': 'app',
      'floorAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final list = _cache;
    if (list != null) {
      list.removeWhere((c) => c.name == name.trim());
      list.add(CenterInfo(name.trim(), floor));
      list.sort((a, b) => a.name.compareTo(b.name));
    }
  }
}
