import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'survey_templates.dart';
import 'survey_photo_service.dart';
import 'survey_camera_screen.dart';
import 'survey_draft_store.dart';
import '../gaetong/gaetong_store.dart' show CenterService;

const _bandGreen = Color(0xFF00A032);

// ==================================================================
// 1. 실사 시작 화면 : 임시저장 목록 → 국소명 → 층 → 상면/입전 → 4G/5G
// ==================================================================
class SurveyStartScreen extends StatefulWidget {
  const SurveyStartScreen({super.key});

  @override
  State<SurveyStartScreen> createState() => _SurveyStartScreenState();
}

class _SurveyStartScreenState extends State<SurveyStartScreen> {
  final Map<String, String> _addressByName = {};
  final _stationCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  String _kind = ''; // 상면 / 입전
  SurveyTemplate? _selected;
  List<SurveyDraft> _drafts = [];
  List<String> _centerNames = []; // 엑셀 통합국 시트 E열 중심국명 (Firebase CenterData)
  final _stationFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    _loadDrafts();
    // 국소명 자동완성용 중심국 목록 (실패해도 직접 입력은 가능)
    CenterService.load(force: true).then((list) {
      if (mounted) setState(() => _centerNames = list.map((c) => c.name).toList());
    }).catchError((_) {});
    _stationFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  /// 입력한 글자가 들어간 중심국명 (띄어쓰기·대소문자 무시, 앞부분 일치 먼저, 최대 8개)
  List<String> _centerMatches() {
    String norm(String x) => x.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final q = norm(_stationCtrl.text);
    if (q.isEmpty) return [];
    final hit = _centerNames.where((n) => norm(n).contains(q)).toList();
    if (hit.length == 1 && hit.first == _station) return []; // 이미 골랐음
    hit.sort((a, b) {
      final pa = norm(a).startsWith(q) ? 0 : 1, pb = norm(b).startsWith(q) ? 0 : 1;
      return pa != pb ? pa - pb : a.compareTo(b);
    });
    return hit.take(8).toList();
  }

  @override
  void dispose() {
    _stationCtrl.dispose();
    _stationFocus.dispose();
    _floorCtrl.dispose();
    super.dispose();
  }

  // 주소록 CSV에서 주소만 찾아 쓰기 (국소명이 정확히 같을 때 본문에 주소 표시)
  Future<void> _loadAddresses() async {
    try {
      String csvString;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/addresses.csv');
      if (await file.exists()) {
        csvString = await file.readAsString();
      } else {
        csvString = await rootBundle.loadString('assets/addresses.csv');
      }
      final rows = const CsvToListConverter().convert(csvString);
      if (rows.isNotEmpty) rows.removeAt(0);
      for (final r in rows) {
        if (r.isEmpty) continue;
        final name = r[0].toString().trim();
        if (name.isEmpty) continue;
        _addressByName[name] = r.length > 1 ? r[1].toString() : '';
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('주소 목록 로드 실패: $e');
    }
  }

  Future<void> _loadDrafts() async {
    final list = await SurveyDraftStore.loadAll();
    if (mounted) setState(() => _drafts = list);
  }

  String get _station => _stationCtrl.text.trim();

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm(SurveyTemplate tpl, String station, String floor,
      SurveyDraft? draft) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyFormScreen(
          station: station,
          floor: floor,
          address: _addressByName[station] ?? '',
          template: tpl,
          draft: draft,
        ),
      ),
    );
    _loadDrafts();
  }

  Future<void> _start() async {
    if (_station.isEmpty) return _snack('국소명을 먼저 입력해주세요.');
    if (_kind.isEmpty) return _snack('상면 실사 / 입전 실사를 선택해주세요.');
    final tpl = _selected;
    if (tpl == null) return _snack('4G / 5G 구분을 선택해주세요.');

    final existing = await SurveyDraftStore.find(_station, tpl.id);
    if (!mounted) return;
    if (existing == null) {
      return _openForm(tpl, _station, _floorCtrl.text.trim(), null);
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('임시저장된 실사가 있습니다'),
        content: Text(
            '$_station\n${DateFormat('MM/dd HH:mm').format(existing.savedAt)} 에 저장된 내용이 있어요.\n이어서 할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'new'),
              child: const Text('지우고 새로 시작',
                  style: TextStyle(color: Colors.red))),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, 'resume'),
              child: const Text('이어서 하기')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'resume') {
      _openForm(tpl, existing.station, existing.floor, existing);
    } else if (choice == 'new') {
      await SurveyDraftStore.remove(existing.id);
      if (!mounted) return;
      _openForm(tpl, _station, _floorCtrl.text.trim(), null);
    }
  }

  Future<void> _deleteDraft(SurveyDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('임시저장 삭제'),
        content: Text('${d.station} 의 임시저장을 지울까요?\n(휴대폰에 저장된 사진은 남아있습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await SurveyDraftStore.remove(d.id);
      _loadDrafts();
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final address = _addressByName[_station] ?? '';
    final floor = _floorCtrl.text.trim();
    final tplList = kSurveyTemplates.where((t) => t.place == _kind).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('실사'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // ----- 임시저장 목록 -----
            if (_drafts.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('임시저장된 실사 ${_drafts.length}건',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.brown.shade700)),
                    ..._drafts.map((d) {
                      final t = templateById(d.templateId);
                      return Card(
                        margin: const EdgeInsets.only(top: 6),
                        child: ListTile(
                          dense: true,
                          title: Text(d.station,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              '${t?.name ?? d.templateId}${d.floor.isNotEmpty ? ' · ${d.floor}층' : ''}\n'
                              '${DateFormat('MM/dd HH:mm').format(d.savedAt)} 저장 · 사진 ${d.photoCount}장'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: t == null
                                    ? null
                                    : () => _openForm(t, d.station, d.floor, d),
                                child: const Text('이어서'),
                              ),
                              IconButton(
                                tooltip: '임시저장 삭제',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _deleteDraft(d),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // ----- ① 국소명 -----
            _title('① 국소명'),
            TextField(
              controller: _stationCtrl,
              focusNode: _stationFocus,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '국소명 입력 (중심국명 일부만 쳐도 아래에 목록이 떠요)',
                prefixIcon: const Icon(Icons.cell_tower),
                border: const OutlineInputBorder(),
                suffixIcon: _stationCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _stationCtrl.clear()),
                      ),
              ),
            ),
            if (_stationFocus.hasFocus && _centerMatches().isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.indigo.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    for (final n in _centerMatches())
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_city, size: 20, color: Colors.indigo),
                        title: Text(n, style: const TextStyle(fontSize: 15)),
                        onTap: () {
                          _stationCtrl.text = n;
                          _stationCtrl.selection = TextSelection.collapsed(offset: n.length);
                          FocusScope.of(context).unfocus();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            if (address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('주소: $address',
                    style: const TextStyle(color: Colors.grey)),
              ),

            // ----- ② 층 -----
            _title('② 층'),
            TextField(
              controller: _floorCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '숫자만 입력 (예: 3)',
                prefixIcon: Icon(Icons.stairs),
                suffixText: '층',
                border: OutlineInputBorder(),
              ),
            ),
            if (floor.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text("밴드에는 '$floor층'으로 표시돼요",
                    style: const TextStyle(color: Colors.grey)),
              ),

            // ----- ③ 실사 종류 -----
            _title('③ 실사 종류'),
            Row(
              children: [
                for (final k in const [
                  ['상면', '상면 실사', '4G / 5G · 신규랙(증설)'],
                  ['입전', '입전 실사', '4G / 5G · 기존랙'],
                ]) ...[
                  Expanded(
                    child: _KindButton(
                      label: k[1],
                      sub: k[2],
                      selected: _kind == k[0],
                      onTap: () => setState(() {
                        _kind = k[0];
                        _selected = null;
                      }),
                    ),
                  ),
                  if (k[0] == '상면') const SizedBox(width: 10),
                ],
              ],
            ),

            // ----- ④ 구분 -----
            if (_kind.isNotEmpty) ...[
              _title('④ $_kind 실사 구분'),
              ...tplList.map((t) {
                final sel = _selected?.id == t.id;
                return Card(
                  elevation: sel ? 3 : 1,
                  color: sel ? Colors.indigo.shade50 : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: sel ? Colors.indigo : Colors.grey.shade300,
                        width: sel ? 2 : 1),
                  ),
                  child: ListTile(
                    onTap: () => setState(() => _selected = t),
                    leading: Icon(
                        sel ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: Colors.indigo),
                    title: Text('${t.tech} · ${t.rack}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(t.summary, style: const TextStyle(fontSize: 12)),
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('실사 시작', style: TextStyle(fontSize: 17)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 설치된 앱이 최신인지 확인용 (코드 바꿀 때마다 올림)
            const Center(
              child: Text('실사 빌드 2026-10-27 #12',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _KindButton(
      {required this.label,
      required this.sub,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.indigo : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text(sub,
                  style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white70 : Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// 2. 실사 입력 화면
// ==================================================================

/// 화면에 그려질 섹션 1개 (예: 정류기2 > 축전지1)
class _Inst {
  final SectionDef def;
  final String path; // 데이터 저장 키 (예: rectifier2/battery1/)
  final String name; // 예: 축전지1
  final String display; // 예: 정류기2 > 축전지1
  final String fileLabel; // 예: 정류기2_축전지1
  final int depth;
  _Inst(this.def, this.path, this.name, this.display, this.fileLabel, this.depth);
}

class SurveyFormScreen extends StatefulWidget {
  final String station;
  final String floor;
  final String address;
  final SurveyTemplate template;
  final SurveyDraft? draft;

  const SurveyFormScreen({
    super.key,
    required this.station,
    required this.floor,
    required this.address,
    required this.template,
    this.draft,
  });

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen> {
  final Map<String, int> _counts = {}; // 반복 섹션 개수
  final Map<String, String> _values = {}; // 입력값
  final Map<String, List<String>> _photos = {}; // 사진 경로
  final Map<String, TextEditingController> _ctrls = {};
  Timer? _saveTimer;
  bool _discarded = false; // 저장 안 하고 나가기 / 완료 처리 후에는 다시 저장하지 않음

  SurveyTemplate get _tpl => widget.template;
  String get _draftId => SurveyDraftStore.makeId(widget.station, _tpl.id);

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d != null) {
      _counts.addAll(d.counts);
      _values.addAll(d.values);
      d.photos.forEach((k, v) => _photos[k] = List<String>.from(v));
    }
  }

  @override
  void dispose() {
    final pending = _saveTimer?.isActive ?? false;
    _saveTimer?.cancel();
    if (pending && !_discarded) _saveDraft(); // 마지막 입력 저장
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------- 임시저장 ----------------
  bool get _hasAnyInput =>
      _values.values.any((v) => v.trim().isNotEmpty) ||
      _photos.values.any((l) => l.isNotEmpty);

  /// 입력이 바뀔 때마다 호출 → 0.8초 뒤 자동 임시저장
  void _changed() {
    if (_discarded) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_discarded || !_hasAnyInput) return;
    await SurveyDraftStore.save(SurveyDraft(
      station: widget.station,
      floor: widget.floor,
      templateId: _tpl.id,
      counts: Map.of(_counts),
      values: Map.of(_values),
      photos: _photos.map((k, v) => MapEntry(k, List<String>.from(v))),
      savedAt: DateTime.now(),
    ));
  }

  void _setValue(String key, String? v) {
    setState(() {
      if (v == null || v.isEmpty) {
        _values.remove(key);
      } else {
        _values[key] = v;
      }
    });
    _changed();
  }

  // ---------------- 키 / 인스턴스 계산 ----------------
  String _countKey(String parentPath, SectionDef def) => '$parentPath${def.id}';
  int _countOf(String parentPath, SectionDef def) =>
      def.repeatable ? (_counts[_countKey(parentPath, def)] ?? 1) : 1;

  _Inst _inst(SectionDef def, int n, String parentPath, String parentDisplay,
      String parentFile, int depth) {
    final name = def.repeatable ? '${def.title}$n' : def.title;
    return _Inst(
      def,
      '$parentPath${def.id}$n/',
      name,
      parentDisplay.isEmpty ? name : '$parentDisplay > $name',
      parentFile.isEmpty ? name : '${parentFile}_$name',
      depth,
    );
  }

  /// 모든 섹션 인스턴스를 화면 순서대로 (본문/사진 순서용)
  List<_Inst> _allInstances() {
    final out = <_Inst>[];
    void walk(SectionDef def, String pp, String pd, String pf, int depth) {
      final n = _countOf(pp, def);
      for (int i = 1; i <= n; i++) {
        final inst = _inst(def, i, pp, pd, pf, depth);
        out.add(inst);
        for (final c in def.children) {
          walk(c, inst.path, inst.display, inst.fileLabel, depth + 1);
        }
      }
    }

    for (final s in _tpl.sections) {
      walk(s, '', '', '', 0);
    }
    return out;
  }

  String _vKey(String path, int r, int f) => '${path}r${r}f$f';
  String _pKey(String path, int r) => '${path}r$r';
  String _cPrefix(int c) => 'check/c$c';
  String _cKey(int c, int f) => '${_cPrefix(c)}f$f';
  String _needKey(int c) => '${_cPrefix(c)}need';

  TextEditingController _ctrl(String key) =>
      _ctrls.putIfAbsent(key, () => TextEditingController(text: _values[key]));

  /// showIf 조건 (예: GPS 가 '증설필요'일 때만 케이블길이 표시)
  bool _visible(FieldDef f, String prefix) {
    if (f.showIfIndex == null) return true;
    return (_values['${prefix}f${f.showIfIndex}'] ?? '') == f.showIfValue;
  }

  // ---------------- 반복 섹션 추가/삭제 ----------------
  void _addInstance(String parentPath, SectionDef def) {
    final n = _countOf(parentPath, def);
    if (n >= def.max) return;
    setState(() => _counts[_countKey(parentPath, def)] = n + 1);
    _changed();
  }

  Future<void> _removeLastInstance(String parentPath, SectionDef def) async {
    final n = _countOf(parentPath, def);
    if (n <= 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${def.title}$n 삭제'),
        content: const Text('입력한 내용과 사진 목록이 지워집니다.\n(휴대폰에 저장된 사진은 남아있습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final prefix = '$parentPath${def.id}$n/';
    setState(() {
      _values.removeWhere((k, _) => k.startsWith(prefix));
      _photos.removeWhere((k, _) => k.startsWith(prefix));
      _counts.removeWhere((k, _) => k.startsWith(prefix));
      final dead = _ctrls.keys.where((k) => k.startsWith(prefix)).toList();
      for (final k in dead) {
        _ctrls.remove(k)?.dispose();
      }
      _counts[_countKey(parentPath, def)] = n - 1;
    });
    _changed();
  }

  // ---------------- 사진 ----------------
  Future<void> _takePhotos(_Inst inst, int r) async {
    final row = inst.def.rows[r];
    final key = _pKey(inst.path, r);
    String label = row.photo ?? '사진';
    // Fuse 줄은 파일명에 FA3 처럼 퓨즈번호를 넣음
    final fi = row.fields.indexWhere((f) => f.type == FieldType.fuse);
    if (fi >= 0) {
      final fv = _fmt(row.fields[fi], _vKey(inst.path, r, fi));
      if (fv.isNotEmpty) label = fv;
    }
    final base = fi >= 0
        ? '${inst.display.split(' > ').first}_$label'
        : '${inst.fileLabel}_$label';

    final list = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyCameraScreen(
          station: widget.station,
          baseName: base,
          label: '${inst.name} · $label',
          startNumber: (_photos[key]?.length ?? 0) + 1,
        ),
      ),
    );
    if (list == null || list.isEmpty || !mounted) return;
    setState(() => (_photos[key] ??= []).addAll(list));
    _changed();
  }

  Future<void> _pickPhotos(_Inst inst, int r) async {
    final key = _pKey(inst.path, r);
    try {
      final paths = await SurveyPhotoService.pickFromGallery(widget.station);
      if (paths.isEmpty || !mounted) return;
      setState(() => (_photos[key] ??= []).addAll(paths));
      _changed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('사진 선택 오류: $e')));
      }
    }
  }

  void _viewPhoto(String key, int idx) {
    final path = _photos[key]![idx];
    showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: InteractiveViewer(child: Image.file(File(path)))),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(path.split('/').last,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => _photos[key]!.removeAt(idx));
                    _changed();
                    Navigator.pop(c);
                  },
                  child: const Text('목록에서 빼기',
                      style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('닫기')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 값 표시 (단위/접두어) ----------------
  String _fmt(FieldDef f, String key) {
    final v = (_values[key] ?? '').trim();
    if (v.isEmpty) return '';
    if (f.type == FieldType.cascade) {
      final sub = (_values['$key.sub'] ?? '').trim();
      return sub.isEmpty ? v : '$v $sub';
    }
    if (f.type == FieldType.fuse) {
      return v + (_values['$key.num'] ?? '').trim();
    }
    String out = v;
    if (f.prefix.isNotEmpty &&
        !out.toUpperCase().startsWith(f.prefix.toUpperCase())) {
      out = f.prefix + out;
    }
    final sx = f.suffix.trim();
    if (sx.isNotEmpty && !out.toUpperCase().endsWith(sx.toUpperCase())) {
      out = out + f.suffix;
    }
    return out;
  }

  // ---------------- 밴드 본문 만들기 ----------------
  String buildBody() {
    final sb = StringBuffer();
    sb.writeln('[실사] ${widget.station}');
    sb.writeln('구분: ${_tpl.place} 실사 / ${_tpl.tech} / ${_tpl.rack}');
    if (widget.floor.isNotEmpty) sb.writeln('층: ${widget.floor}층');
    if (widget.address.isNotEmpty) sb.writeln('주소: ${widget.address}');
    sb.writeln('실사일: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}');

    for (final inst in _allInstances()) {
      final lines = <String>[];
      int photoCount = 0;
      for (int r = 0; r < inst.def.rows.length; r++) {
        final row = inst.def.rows[r];
        photoCount += _photos[_pKey(inst.path, r)]?.length ?? 0;
        for (int f = 0; f < row.fields.length; f++) {
          final field = row.fields[f];
          final v = _fmt(field, _vKey(inst.path, r, f));
          if (v.isEmpty) continue;
          lines.add(field.type == FieldType.memo
              ? '- ${field.label}:\n$v'
              : '- ${field.label}: $v');
        }
      }
      if (lines.isEmpty && photoCount == 0) continue;
      sb.writeln();
      sb.writeln('■ ${inst.display}${photoCount > 0 ? ' (사진 $photoCount장)' : ''}');
      for (final l in lines) {
        sb.writeln(l);
      }
    }

    // 확인필요사항: [필요] 로 고른 것만
    final checkLines = <String>[];
    for (int c = 0; c < _tpl.checks.length; c++) {
      if (_values[_needKey(c)] != '1') continue;
      final chk = _tpl.checks[c];
      final parts = <String>[];
      for (int f = 0; f < chk.fields.length; f++) {
        final field = chk.fields[f];
        if (!_visible(field, _cPrefix(c))) continue;
        final v = _fmt(field, _cKey(c, f));
        if (v.isEmpty) continue;
        // GPS: 증설필요 처럼 항목명과 칸 이름이 같으면 값만
        parts.add(field.label == chk.label ? v : '${field.label} $v');
      }
      checkLines.add('- ${chk.label}: ${parts.isEmpty ? '필요' : parts.join(' / ')}');
    }
    if (checkLines.isNotEmpty) {
      sb.writeln();
      sb.writeln('■ 확인필요사항');
      for (final l in checkLines) {
        sb.writeln(l);
      }
    }
    return sb.toString().trimRight();
  }

  List<String> allPhotoPaths() {
    final out = <String>[];
    for (final inst in _allInstances()) {
      for (int r = 0; r < inst.def.rows.length; r++) {
        out.addAll(_photos[_pKey(inst.path, r)] ?? const []);
      }
    }
    return out;
  }

  Future<void> _goPreview() async {
    await _saveDraft();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyPreviewScreen(
          station: widget.station,
          body: buildBody(),
          photos: allPhotoPaths(),
          draftId: _draftId,
          onCompleted: () {
            _discarded = true;
            _saveTimer?.cancel();
          },
        ),
      ),
    );
  }

  Future<void> _onBack() async {
    if (!_hasAnyInput) {
      Navigator.pop(context);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('나가기'),
        content: const Text(
            '입력한 내용을 임시저장할까요?\n실사 첫 화면에서 언제든 이어서 할 수 있어요.\n(촬영한 사진은 휴대폰에 항상 남아있습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'stay'),
              child: const Text('계속 입력')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: const Text('저장 안 하고 나가기',
                  style: TextStyle(color: Colors.red))),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('임시저장하고 나가기')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      _saveTimer?.cancel();
      await _saveDraft();
      if (mounted) Navigator.pop(context);
    } else if (choice == 'discard') {
      _discarded = true;
      _saveTimer?.cancel();
      await SurveyDraftStore.remove(_draftId);
      if (mounted) Navigator.pop(context);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.station, style: const TextStyle(fontSize: 17)),
              Text(
                  '${_tpl.name}${widget.floor.isNotEmpty ? ' · ${widget.floor}층' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: () async {
                _saveTimer?.cancel();
                await _saveDraft();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('임시저장되었습니다.')));
                }
              },
              child: const Text('임시저장', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
          children: [
            ..._tpl.sections.map((s) => Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _buildSection(s, '', '', '', 0),
                  ),
                )),
            _buildChecks(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _goPreview,
                icon: const Icon(Icons.preview),
                label: Text('밴드 본문 미리보기 (사진 ${allPhotoPaths().length}장)',
                    style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _bandGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(SectionDef def, String pp, String pd, String pf, int depth) {
    final n = _countOf(pp, def);
    final widgets = <Widget>[];

    for (int i = 1; i <= n; i++) {
      final inst = _inst(def, i, pp, pd, pf, depth);
      widgets.add(_buildInstance(inst, isLast: i == n, total: n, parentPath: pp));
    }

    if (def.repeatable && n < def.max) {
      widgets.add(Padding(
        padding: EdgeInsets.only(left: depth * 12.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addInstance(pp, def),
            icon: const Icon(Icons.add_circle_outline),
            label: Text('${def.title} 추가 (${n + 1}/${def.max})'),
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widgets);
  }

  Widget _buildInstance(_Inst inst,
      {required bool isLast, required int total, required String parentPath}) {
    final def = inst.def;
    final headerColor = inst.depth == 0 ? Colors.indigo : Colors.teal.shade700;

    return Container(
      margin: EdgeInsets.only(left: inst.depth * 8.0, bottom: 8),
      padding: inst.depth > 0 ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: inst.depth > 0
          ? BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(inst.depth == 0 ? Icons.label : Icons.subdirectory_arrow_right,
                  color: headerColor, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(inst.name,
                    style: TextStyle(
                        fontSize: inst.depth == 0 ? 18 : 16,
                        fontWeight: FontWeight.bold,
                        color: headerColor)),
              ),
              if (def.repeatable && isLast && total > 1)
                IconButton(
                  tooltip: '${inst.name} 삭제',
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () => _removeLastInstance(parentPath, def),
                ),
            ],
          ),
          if (def.note != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Text('※ ${def.note}',
                  style: const TextStyle(color: Colors.deepOrange, fontSize: 12)),
            ),
          for (int r = 0; r < def.rows.length; r++) _buildRow(inst, r),
          for (final child in def.children)
            _buildSection(child, inst.path, inst.display, inst.fileLabel, inst.depth + 1),
        ],
      ),
    );
  }

  Widget _buildRow(_Inst inst, int r) {
    final row = inst.def.rows[r];
    final pKey = _pKey(inst.path, r);
    final photos = _photos[pKey] ?? const <String>[];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (row.photo != null)
            Row(
              children: [
                Icon(Icons.circle,
                    size: 10, color: photos.isEmpty ? Colors.grey : Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(row.photo!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (photos.isNotEmpty)
                  Text('${photos.length}장 ',
                      style: const TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                IconButton(
                  tooltip: '카메라 (연속 촬영)',
                  icon: const Icon(Icons.photo_camera, color: Colors.indigo),
                  onPressed: () => _takePhotos(inst, r),
                ),
                IconButton(
                  tooltip: '갤러리 (여러 장 선택)',
                  icon: const Icon(Icons.photo_library, color: Colors.indigo),
                  onPressed: () => _pickPhotos(inst, r),
                ),
              ],
            ),
          if (photos.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _viewPhoto(pKey, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(photos[i]),
                        width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 160),
                  ),
                ),
              ),
            ),
          for (int f = 0; f < row.fields.length; f++)
            if (_visible(row.fields[f], pKey))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildField(row.fields[f], _vKey(inst.path, r, f)),
              ),
        ],
      ),
    );
  }

  Widget _buildField(FieldDef f, String key) {
    switch (f.type) {
      case FieldType.choice:
        return _choiceChips(f.label, f.options, key);
      case FieldType.cascade:
        final first = _values[key];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _choiceChips(f.label, f.cascade.keys.toList(), key, clearSub: true),
            if (first != null && first.isNotEmpty && f.cascade[first] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: _choiceChips('$first 용량', f.cascade[first]!, '$key.sub'),
              ),
          ],
        );
      case FieldType.fuse:
        final numKey = '$key.num';
        final fuseShown = _fmt(f, key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${f.label} (FA/FB 선택 후 숫자 입력)',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Row(
              children: [
                ...f.options.map((o) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(o),
                        selected: _values[key] == o,
                        selectedColor: Colors.indigo.shade100,
                        onSelected: (_) =>
                            _setValue(key, _values[key] == o ? null : o),
                      ),
                    )),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _ctrl(numKey),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _setValue(numKey, v),
                    decoration: const InputDecoration(
                      hintText: '숫자',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(_values[key] == null ? '' : fuseShown,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo)),
              ],
            ),
          ],
        );
      case FieldType.text:
      case FieldType.number:
      case FieldType.memo:
        final hasUnit = f.prefix.isNotEmpty || f.suffix.isNotEmpty;
        final shown = hasUnit ? _fmt(f, key) : '';
        String label = f.label;
        if (f.prefix.isNotEmpty) label += ' (앞에 ${f.prefix} 자동)';
        if (f.suffix.trim().isNotEmpty) label += ' (${f.suffix.trim()})';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl(key),
              keyboardType: f.type == FieldType.number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : (f.type == FieldType.memo
                      ? TextInputType.multiline
                      : TextInputType.text),
              maxLines: f.type == FieldType.memo ? 4 : 1,
              onChanged: (v) => _setValue(key, v),
              decoration: InputDecoration(
                labelText: label,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (shown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2),
                child: Text('밴드 표시: $shown',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
              ),
          ],
        );
    }
  }

  Widget _choiceChips(String label, List<String> options, String key,
      {bool clearSub = false}) {
    final cur = _values[key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Wrap(
          spacing: 6,
          children: options.map((o) {
            final sel = cur == o;
            return ChoiceChip(
              label: Text(o),
              selected: sel,
              selectedColor: Colors.indigo.shade100,
              onSelected: (_) {
                setState(() {
                  if (sel) {
                    _values.remove(key);
                  } else {
                    _values[key] = o;
                  }
                  if (clearSub) _values.remove('$key.sub');
                });
                _changed();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChecks() {
    return Card(
      elevation: 2,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.checklist, color: Colors.deepOrange),
                SizedBox(width: 6),
                Text('확인필요사항',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange)),
              ],
            ),
            const SizedBox(height: 6),
            for (int c = 0; c < _tpl.checks.length; c++)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: _buildCheck(c),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheck(int c) {
    final chk = _tpl.checks[c];
    final on = _values[_needKey(c)] == '1';
    final visibleFields = <int>[
      for (int f = 0; f < chk.fields.length; f++)
        if (_visible(chk.fields[f], _cPrefix(c))) f
    ];
    final hasChoice = chk.fields.any((f) => f.type == FieldType.choice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(chk.label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            ChoiceChip(
              label: const Text('불필요'),
              selected: !on,
              selectedColor: Colors.indigo.shade100,
              onSelected: (_) => _setValue(_needKey(c), null),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('필요'),
              selected: on,
              selectedColor: Colors.orange.shade200,
              onSelected: (_) => _setValue(_needKey(c), '1'),
            ),
          ],
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: hasChoice
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final f in visibleFields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildField(chk.fields[f], _cKey(c, f)),
                        ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in visibleFields) ...[
                        if (f != visibleFields.first) const SizedBox(width: 8),
                        Expanded(child: _buildField(chk.fields[f], _cKey(c, f))),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }
}

// ==================================================================
// 3. 밴드 미리보기 / 업로드 화면
// ==================================================================
class SurveyPreviewScreen extends StatefulWidget {
  final String station;
  final String body;
  final List<String> photos;
  final String draftId;
  final VoidCallback? onCompleted;
  final String kind; // 실사 / 개통
  final List<String>? photoLabels; // 사진마다 위쪽에 새길 글자 (photos 와 같은 순서, 없으면 안 새김)

  const SurveyPreviewScreen({
    super.key,
    required this.station,
    required this.body,
    required this.photos,
    required this.draftId,
    this.onCompleted,
    this.kind = '실사',
    this.photoLabels,
  });

  @override
  State<SurveyPreviewScreen> createState() => _SurveyPreviewScreenState();
}

class _SurveyPreviewScreenState extends State<SurveyPreviewScreen> {
  late final TextEditingController _bodyCtrl =
      TextEditingController(text: widget.body);

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _shareToBand() async {
    final text = _bodyCtrl.text;
    // 밴드가 공유 본문을 못 받는 경우를 대비해 클립보드에도 복사
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('밴드에 올리기'),
        content: Text('본문이 복사되었습니다.\n\n'
            '1. 밴드 앱이 바로 열립니다.\n'
            '2. 올릴 밴드를 고르면 사진 ${widget.photos.length}장과 본문이 들어갑니다.\n'
            '3. 본문이 비어 있으면 입력칸을 길게 눌러 [붙여넣기] 하세요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('밴드 열기')),
        ],
      ),
    );
    if (go != true) return;

    // 1) 밴드 앱으로 바로 열기
    String status;
    try {
      status = await const MethodChannel('f2telecom/band').invokeMethod<String>(
            'shareToBand',
            {
              // label 이 비어 있으면 사진에 글자를 새기지 않고 원본 그대로 전달
              'items': [
                for (var i = 0; i < widget.photos.length; i++)
                  {
                    'path': widget.photos[i],
                    'label': (widget.photoLabels != null && i < widget.photoLabels!.length) ? widget.photoLabels![i] : '',
                  }
              ],
              'text': text,
            },
          ) ??
          'null';
    } catch (e) {
      status = 'error: $e';
    }
    if (status == 'ok') {
      if (mounted) _askCompleted();
      return;
    }

    // 2) 밴드가 없거나 실패하면 일반 공유 창으로 (이유를 함께 표시)
    final reason = status == 'no_band'
        ? '밴드 앱이 설치되어 있지 않습니다'
        : status == 'no_activity'
            ? '밴드 앱이 공유를 받지 않습니다'
            : status;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('밴드 바로 열기 실패'),
        content: Text('이유: $reason\n\n확인을 누르면 공유 창이 열립니다. [밴드]를 선택하세요.\n(이 화면을 캡처해서 보내주시면 원인을 고칠 수 있어요)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인')),
        ],
      ),
    );
    if (!mounted) return;
    try {
      // subject(제목)를 같이 넘기면 밴드가 본문 위에 한 번 더 붙이므로 본문만 전달
      if (widget.photos.isEmpty) {
        await Share.share(text);
      } else {
        await Share.shareXFiles(
          widget.photos.map((p) => XFile(p)).toList(),
          text: text,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('공유 실패: $e')));
      }
      return;
    }
    if (!mounted) return;
    _askCompleted();
  }

  Future<void> _askCompleted() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('밴드 등록을 마쳤나요?'),
        content: Text(
            '밴드에 다 올렸으면 이 ${widget.kind}을(를) 완료 처리하고 임시저장을 지웁니다.\n아직이면 [나중에]를 누르세요 (임시저장 유지).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('나중에')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('완료 (임시저장 삭제)')),
        ],
      ),
    );
    if (done != true) return;
    widget.onCompleted?.call();
    await SurveyDraftStore.remove(widget.draftId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${widget.kind} 완료!')));
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('밴드 본문 미리보기'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '본문 복사',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _bodyCtrl.text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('본문이 복사되었습니다.')));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('본문 (여기서 바로 고칠 수 있어요)',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          TextField(
            controller: _bodyCtrl,
            maxLines: null,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text('첨부 사진 ${widget.photos.length}장',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: widget.photos
                .map((p) => Image.file(File(p), fit: BoxFit.cover, cacheWidth: 200))
                .toList(),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _shareToBand,
              icon: const Icon(Icons.upload),
              label: const Text('밴드에 올리기', style: TextStyle(fontSize: 17)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _bandGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
