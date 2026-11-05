import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../survey/survey_camera_screen.dart';
import '../survey/survey_photo_service.dart';
import '../survey/survey_screen.dart' show SurveyPreviewScreen;
import '../survey/record_list_sheet.dart';
import '../survey/photo_viewer_page.dart';
import 'gaetong_model.dart';
import 'gaetong_store.dart';

// ============================================================
// 개통 (홈 메뉴 '자료' 자리, 권한 키 material 유지)
//  시작 화면 → 입력 화면 → 밴드 본문 미리보기(실사와 같은 화면) → 밴드 올리기
// ============================================================

const _indigo = Color(0xFF3F51B5);
const _indigoDark = Color(0xFF283593);
const _ink = Color(0xFF1F2330);
const _sub = Color(0xFF5F6473);
const _teal = Color(0xFF00695C);
const _doneBg = Color(0xFFE3E6EB);
const _doneBorder = Color(0xFFD0D4DC);
const _buildMark = '개통 빌드 2026-11-05 #31';
const _sensingKey = 'sensing'; // 센싱 사진 (갤러리에서 여러 장, 글자 안 새김, 밴드에 맨 먼저)

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

// ============================================================
// 1. 시작 화면
// ============================================================
class GaetongStartScreen extends StatefulWidget {
  const GaetongStartScreen({super.key});
  @override
  State<GaetongStartScreen> createState() => _GaetongStartScreenState();
}

class _GaetongStartScreenState extends State<GaetongStartScreen> {
  final _stationCtrl = TextEditingController();
  final _templates = gaetongTemplates();
  int _tpl = -1;
  List<GaetongDraft> _drafts = [];
  List<GaetongDraft> _recent = [];
  List<CenterInfo> _centers = [];
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
    CenterService.myScore().then((s) {
      if (mounted) setState(() => _score = s);
    }).catchError((_) {});
    // 통합국 목록은 개통 화면을 열 때마다 새로 받음 (엑셀에서 고친 국사정보 반영, 실패해도 입력은 가능)
    CenterService.load(force: true).then((c) {
      if (mounted) setState(() => _centers = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _stationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDrafts() async {
    final d = await GaetongDraftStore.loadAll();
    final r = await GaetongRecentStore.loadAll();
    if (mounted) {
      setState(() {
        _drafts = d;
        _recent = r;
      });
    }
  }

  // 최근 작성 불러오기 → 새 국소명 입력 → 같은 내용으로 새 개통 시작 (사진은 새로)
  Future<void> _reuse(GaetongDraft d) async {
    final tpl = _tplByName(d.tplName);
    if (tpl == null) return;
    // 불러오기 방법: 본문만(국소명 새로) / 전체 내용(사진 포함, 완료 전 화면 그대로)
    final how = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('${d.station.split('\n').first}\n${d.tplName} · ${DateFormat('M/d HH:mm').format(d.savedAt)} 완료'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'full'),
            child: const ListTile(
              leading: Icon(Icons.photo_library_outlined, color: _indigo),
              title: Text('전체 내용 불러오기 (사진 포함)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('완료 전 화면 그대로 · 빠진 사진·내용을 고쳐서 다시 올릴 때'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'body'),
            child: const ListTile(
              leading: Icon(Icons.edit_note, color: _indigo),
              title: Text('본문만 불러오기 (새 국소명)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('같은 장비 구성을 다른 국소에 쓸 때 · 사진은 새로'),
            ),
          ),
          SimpleDialogOption(onPressed: () => Navigator.pop(c), child: const Text('취소', textAlign: TextAlign.right)),
        ],
      ),
    );
    if (how == null || !mounted) return;
    if (how == 'full') {
      final ex = await GaetongDraftStore.find(d.station, d.tplName);
      if (ex != null && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('같은 국소의 임시저장이 있어요'),
            content: const Text('완료했던 내용으로 다시 열면 지금 임시저장된 내용은 바뀌어요. 계속할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
              ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('완료 내용으로 열기')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
      setState(() => _tpl = _templates.indexOf(tpl));
      return _open(tpl, d.station, Map.of(d.values), d.photos.map((k, v) => MapEntry(k, List.of(v))));
    }
    final ctrl = TextEditingController();
    final st = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('불러와서 새로 쓰기'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d.tplName} · ${d.station.split('\n').first}\n입력 내용을 그대로 가져와요. (사진은 새로 찍어야 해요)\n선번처럼 국소마다 다른 칸은 꼭 확인해주세요.',
              style: const TextStyle(fontSize: 13, color: _sub)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 1,
            maxLines: null,
            decoration: const InputDecoration(labelText: '새 국소명', hintText: '여러 개면 줄을 바꿔서', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
          ElevatedButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('시작')),
        ],
      ),
    );
    if (st == null || st.isEmpty || !mounted) return;
    _stationCtrl.text = st;
    setState(() => _tpl = _templates.indexOf(tpl));
    await _startWith(st, tpl, Map.of(d.values)..removeWhere((k, _) => k.endsWith('.open')));
  }

  // 완료 기록 삭제: 한 번 더 확인 (앱에 보관된 사진도 같이 지워짐)
  Future<bool> _deleteRecent(GaetongDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('완료 기록 삭제'),
        content: Text('${recordTitle(d.station)} · ${d.tplName}\n${DateFormat('M/d HH:mm').format(d.savedAt)} 완료 · 사진 ${d.photoCount}장\n\n'
            '이 기록을 목록에서 지울까요?\n앱에 보관된 사진도 같이 지워져요. (휴대폰 갤러리 사진은 남아요)\n지우면 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return false;
    await GaetongRecentStore.remove(d.id);
    await _loadDrafts();
    if (mounted) _toast(context, '완료 기록을 지웠어요');
    return true;
  }

  GTemplate? _tplByName(String name) {
    for (final t in _templates) {
      if (t.name == name) return t;
    }
    return null;
  }

  Future<void> _open(GTemplate tpl, String station, Map<String, String> values, Map<String, List<String>> photos) async {
    // 입력 화면을 열 때마다 통합국 목록을 새로 받음 (엑셀에서 고치거나 지운 중심국 바로 반영)
    try {
      _centers = await CenterService.load(force: true).timeout(const Duration(seconds: 5));
    } catch (_) {
      if (_centers.isEmpty) {
        try {
          _centers = await CenterService.load();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GaetongFormScreen(
          tpl: gaetongTemplates().firstWhere((t) => t.name == tpl.name),
          station: station,
          values: values,
          photos: photos,
          centers: _centers,
          // 개통을 쓸 수 있는 사람(조회 이상)은 모두 국사정보 수정 가능 (2026-11-05)
          canEditCenter: _score >= 2,
        ),
      ),
    );
    _loadDrafts();
  }

  Future<void> _start() async {
    final st = _stationCtrl.text.trim();
    if (st.isEmpty) return _toast(context, '국소명을 먼저 입력해주세요.');
    if (_tpl < 0) return _toast(context, '장비 구분을 선택해주세요.');
    await _startWith(st, _templates[_tpl], null);
  }

  /// values 가 있으면 그 내용으로 시작 (최근 작성 불러오기), 없으면 기본값
  Future<void> _startWith(String st, GTemplate tpl, Map<String, String>? values) async {
    final ex = await GaetongDraftStore.find(st, tpl.name);
    if (!mounted) return;
    if (ex != null) {
      final c = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('임시저장된 개통이 있습니다'),
          content: Text('${st.split('\n').first}\n${DateFormat('M/d HH:mm').format(ex.savedAt)} 에 저장된 내용이 있어요.\n이어서 할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(c, 'new'), child: const Text('지우고 새로 시작', style: TextStyle(color: Colors.red))),
            ElevatedButton(onPressed: () => Navigator.pop(c, 'go'), child: const Text('이어서 하기')),
          ],
        ),
      );
      if (c == 'go') return _open(tpl, ex.station, Map.of(ex.values), ex.photos.map((k, v) => MapEntry(k, List.of(v))));
      if (c != 'new' || !mounted) return;
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('정말 지우고 새로 시작할까요?'),
          content: const Text('임시저장된 내용이 모두 삭제되고 되돌릴 수 없어요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제하고 새로 시작', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (sure != true) return;
      await GaetongDraftStore.remove(ex.id);
    }
    _open(tpl, st, values ?? GaetongModel.defaults(tpl), {});
  }

  Future<bool> _deleteDraft(GaetongDraft d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('임시저장 삭제'),
        content: Text('${recordTitle(d.station)} · ${d.tplName}\n${DateFormat('M/d HH:mm').format(d.savedAt)} 저장 · 사진 ${d.photoCount}장\n\n'
            '이 임시저장을 지울까요?\n입력한 내용이 모두 지워지고 되돌릴 수 없어요. (휴대폰 갤러리 사진은 남아요)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return false;
    await GaetongDraftStore.remove(d.id);
    await _loadDrafts();
    if (mounted) _toast(context, '임시저장을 지웠어요');
    return true;
  }

  // 목록 시트 (임시저장 / 완료한 개통)
  void _showDrafts() {
    showRecordListSheet(
      context,
      title: (n) => '임시저장된 개통 $n건',
      sub: '최근 저장 순 · [이어서] 누르면 하던 곳부터',
      color: const Color(0xFF8D5A00),
      entries: [
        for (final d in _drafts)
          RecordEntry(
            station: d.station,
            sub: '${d.tplName} · ${DateFormat('M/d HH:mm').format(d.savedAt)} 저장 · 사진 ${d.photoCount}장',
            at: d.savedAt,
            action: '이어서',
            onOpen: () async {
              final t = _tplByName(d.tplName);
              if (t != null) await _open(t, d.station, Map.of(d.values), d.photos.map((k, v) => MapEntry(k, List.of(v))));
            },
            onDelete: () => _deleteDraft(d),
          ),
      ],
    );
  }

  void _showRecent() {
    showRecordListSheet(
      context,
      title: (n) => '완료한 개통 $n건',
      sub: '최근 완료 순 · ${GaetongRecentStore.keepDays}일 지나면 자동으로 지워져요',
      color: _indigoDark,
      entries: [
        for (final d in _recent)
          RecordEntry(
            station: d.station,
            sub: '${d.tplName} · ${DateFormat('M/d HH:mm').format(d.savedAt)} 완료 · 사진 ${d.photoCount}장',
            at: d.savedAt,
            action: '불러오기',
            onOpen: () => _reuse(d),
            onDelete: () => _deleteRecent(d),
          ),
      ],
    );
  }

  Widget _kindButton(int i) {
    final t = _templates[i];
    final sel = _tpl == i;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _tpl = i),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: sel ? _indigo : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _indigo : const Color(0xFFD5D8E2), width: sel ? 2 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(t.btnSmall ?? t.tech, style: TextStyle(fontSize: 12, color: sel ? Colors.white70 : _sub)),
          Text(t.btnBig ?? t.eq, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sel ? Colors.white : _ink)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final five = [for (var i = 0; i < _templates.length; i++) if (_templates[i].tech == '5G') i];
    final four = [for (var i = 0; i < _templates.length; i++) if (_templates[i].tech == '4G') i];
    final dus = [for (var i = 0; i < _templates.length; i++) if (_templates[i].tech == 'DU') i];
    // padding 0: 기본값이면 화면 위·아래 여백(상태바·내비바 높이)이 그리드마다 붙어 간격이 크게 벌어짐
    Widget grid(List<int> idx) => GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: idx.map(_kindButton).toList(),
        );
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(title: const Text('개통'), backgroundColor: _indigo, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_drafts.isNotEmpty || _recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: RecordCountButton(
                      icon: Icons.save_outlined,
                      label: '임시저장',
                      count: _drafts.length,
                      hint: '눌러서 이어서 하기 ›',
                      bg: const Color(0xFFFFF8E1),
                      border: const Color(0xFFFFD54F),
                      fg: const Color(0xFF8D5A00),
                      onTap: _showDrafts,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RecordCountButton(
                      icon: Icons.check_circle_outline,
                      label: '완료한 개통',
                      count: _recent.length,
                      hint: '${GaetongRecentStore.keepDays}일 보관 · 불러오기 ›',
                      bg: const Color(0xFFE8EAF6),
                      border: const Color(0xFFC5CAE9),
                      fg: _indigoDark,
                      onTap: _showRecent,
                    ),
                  ),
                ]),
              ),
            ),
          const Text('① 국소명', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _stationCtrl,
            minLines: 2,
            maxLines: null,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: '국소명 직접 입력 (여러 개면 줄을 바꿔서)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 22),
          const Text('② 장비 구분', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('5G', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _indigoDark)),
          const SizedBox(height: 6),
          grid(five),
          const SizedBox(height: 14),
          const Text('4G', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFBF360C))),
          const SizedBox(height: 6),
          grid(four),
          const SizedBox(height: 14),
          const Text('DU', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _teal)),
          const SizedBox(height: 6),
          grid(dus),
          const SizedBox(height: 16),
          const Center(child: Text(_buildMark, style: TextStyle(fontSize: 11, color: Colors.grey))),
        ],
      ),
      // 시작 버튼은 화면 맨 아래 고정 (스크롤 안 해도 보임) — 국소명·장비를 다 고르면 진한 색
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE3E5EC)))),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _stationCtrl,
          builder: (_, v, __) {
            final ready = _tpl >= 0 && v.text.trim().isNotEmpty;
            return SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _start,
                style: ElevatedButton.styleFrom(
                    backgroundColor: ready ? _indigo : const Color(0xFF9FA8DA),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder()),
                child: Text(_tpl >= 0 ? '${_templates[_tpl].name} 개통 입력 시작' : '개통 입력 시작',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// 2. 입력 화면
// ============================================================
class GaetongFormScreen extends StatefulWidget {
  final GTemplate tpl;
  final String station;
  final Map<String, String> values;
  final Map<String, List<String>> photos;
  final List<CenterInfo> centers;
  final bool canEditCenter; // '수정' 권한: 통합국에 이미 있는 국사정보를 바꿀 수 있음

  const GaetongFormScreen({
    super.key,
    required this.tpl,
    required this.station,
    required this.values,
    required this.photos,
    required this.centers,
    this.canEditCenter = false,
  });

  @override
  State<GaetongFormScreen> createState() => _GaetongFormScreenState();
}

class _GaetongFormScreenState extends State<GaetongFormScreen> {
  late final GaetongModel m;
  late final Map<String, List<String>> _photos = widget.photos;
  late final Map<String, String> _defaults = GaetongModel.defaults(widget.tpl);
  Timer? _saveTimer;
  bool _savingCenter = false;
  // [돌아가서 입력] → 빠진 첫 칸으로 이동 + 주황 테두리 (3초)
  final Map<String, GlobalKey> _jumpKeys = {};
  String? _flashKey;
  bool _flashText = false;
  Timer? _flashTimer;
  GlobalKey _jk(String k) => _jumpKeys.putIfAbsent(k, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    m = GaetongModel(widget.tpl,
        station: widget.station, values: widget.values, centers: widget.centers, onChanged: _changed);
    m.hasPhoto = (k) => (_photos[k] ?? const <String>[]).isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recalcDup());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _jumpTo((String, bool) miss) {
    setState(() {
      _flashKey = miss.$1;
      _flashText = miss.$2;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _jumpKeys[miss.$1]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.25, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flashKey = null);
    });
  }

  // 빠진 칸 표시: 주황 테두리
  Widget _flashWrap(String k, Widget child) {
    final on = _flashKey == k;
    return AnimatedContainer(
      key: _jk(k),
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? const Color(0xFFEF6C00) : Colors.transparent, width: 2),
        color: on ? const Color(0xFFFFF3E0) : Colors.transparent,
      ),
      padding: const EdgeInsets.all(2),
      child: child,
    );
  }

  String get _draftId => GaetongDraftStore.makeId(widget.station, widget.tpl.name);

  bool get _hasInput {
    if (_photos.values.any((l) => l.isNotEmpty)) return true;
    final a = Map.of(m.values)..removeWhere((k, v) => k.endsWith('.open'));
    final b = Map.of(_defaults);
    if (a.length != b.length) return true;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return true;
    }
    return false;
  }

  // 입력할 때마다 자동 임시저장 (0.6초 모아서)
  void _changed() {
    if (!mounted) return;
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
    _recalcDup();
  }

  // ---------------- 겹친 사진 표시 ----------------
  // 같은 사진이 다른 칸에도 있으면 작은 사진에 '○○에도 있음', 같은 칸에 두 번이면 '중복' 표시
  Map<String, String> _dupNote = {};
  String _dupSnap = '';

  Future<void> _recalcDup() async {
    final all = <(String, String)>[for (final e in _photos.entries) for (final p in e.value) (e.key, p)];
    final snap = all.map((x) => '${x.$1}|${x.$2}').join(',');
    if (snap == _dupSnap) return;
    _dupSnap = snap;
    final groups = <String, List<(String, String)>>{};
    final idsOf = <(String, String), List<String>>{};
    for (final x in all) {
      final sig = await _sig(x.$2);
      final ids = [if (sig.isNotEmpty) 's:$sig', 'n:${_origName(x.$2)}'];
      idsOf[x] = ids;
      for (final id in ids) {
        (groups[id] ??= []).add(x);
      }
    }
    final note = <String, String>{};
    for (final x in all) {
      final others = <(String, String)>{
        for (final id in idsOf[x]!) ...groups[id]!.where((o) => o != x),
      };
      if (others.isEmpty) continue;
      if (others.any((o) => o.$1 == x.$1)) {
        note[x.$2] = '중복';
      } else {
        note[x.$2] = '${_slotName(others.first.$1)}에도 있음';
      }
    }
    if (!mounted || snap != _dupSnap) return;
    final same = note.length == _dupNote.length && note.entries.every((e) => _dupNote[e.key] == e.value);
    if (!same) setState(() => _dupNote = note);
  }

  Future<void> _saveDraft() async {
    if (!_hasInput) return;
    await GaetongDraftStore.save(GaetongDraft(
      station: widget.station.trim(),
      tplName: widget.tpl.name,
      values: Map.of(m.values),
      photos: _photos.map((k, v) => MapEntry(k, List.of(v))),
      savedAt: DateTime.now(),
    ));
  }

  Future<void> _onBack() async {
    if (!_hasInput) {
      _saveTimer?.cancel();
      await GaetongDraftStore.remove(_draftId);
      if (mounted) Navigator.pop(context);
      return;
    }
    final c = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('나가기'),
        content: const Text('입력한 내용을 임시저장할까요?\n개통 첫 화면에서 언제든 이어서 할 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'stay'), child: const Text('계속 입력')),
          TextButton(onPressed: () => Navigator.pop(c, 'drop'), child: const Text('저장 안 하고 나가기', style: TextStyle(color: Colors.red))),
          ElevatedButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('임시저장하고 나가기')),
        ],
      ),
    );
    if (!mounted) return;
    if (c == 'save') {
      _saveTimer?.cancel();
      await _saveDraft();
      if (mounted) {
        _toast(context, '임시저장되었습니다.');
        Navigator.pop(context);
      }
    } else if (c == 'drop') {
      // 실수로 지우지 않게 한 번 더 확인
      final sure = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('정말 저장 안 하고 나갈까요?'),
          content: const Text('지금까지 입력한 내용과 사진 목록이 모두 삭제되고 되돌릴 수 없어요.\n(휴대폰에 저장된 사진은 남아있습니다)'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'stay'), child: const Text('계속 입력')),
            TextButton(onPressed: () => Navigator.pop(c, 'drop'), child: const Text('삭제하고 나가기', style: TextStyle(color: Colors.red))),
            ElevatedButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('임시저장하고 나가기')),
          ],
        ),
      );
      if (!mounted) return;
      _saveTimer?.cancel();
      if (sure == 'save') {
        await _saveDraft();
        if (mounted) Navigator.pop(context);
      } else if (sure == 'drop') {
        await GaetongDraftStore.remove(_draftId);
        if (mounted) Navigator.pop(context);
      }
    }
  }

  /// 사진 자리 (화면 순서): 키, 사진 위에 새길 글자 ('' 이면 안 새김)
  List<(String, String)> _photoSlots() {
    // 센싱 사진은 밴드에 본문 다음 맨 먼저 (사진 위 글자 없음)
    // DU 는 센싱 없음
    final out = <(String, String)>[if (widget.tpl.tech != 'DU') (_sensingKey, '')];
    for (var si = 0; si < widget.tpl.sections.length; si++) {
      final sec = widget.tpl.sections[si];
      if (sec.photo) out.add((_secKey(sec), _secLabel(sec)));
      for (final x in m.items.where((x) => x.si == si)) {
        switch (x.it.type) {
          case 'link':
            for (var i = 1; i <= m.linkCount(x.key); i++) {
              out.add(('${x.key}.$i.ph', '정류기 $i'));
            }
            break;
          case 'sunU': {
            final src = m.sunSource(x.it);
            if (src == null) break;
            for (final en in src.entries) {
              final lab = m.sunLabel(src.it, en);
              final slots = m.sunSlots(src.it, en, x.key);
              for (final sl in slots) {
                out.add((sl.$2, _sunStamp(x.it, slots.length > 1 ? '$lab (${sl.$1})' : lab)));
              }
            }
            break;
          }
          case 'photo':
            out.add((x.key, ''));
            break;
        }
      }
    }
    return out;
  }

  /// 선번 사진 글자: '중심국 MUX~사업자OFD_3층' / '리모트 IJP~L-MUX'
  String _sunStamp(GItem sunIt, String lab) => '${sunIt.sunFrom == 'rmats' ? '리모트' : '중심국'} $lab';

  String _secKey(GSection s) => 'sec:${s.title}';
  String _secLabel(GSection s) => s.title.replaceAll(' · ', '·');

  List<String> get _allPhotos => [
        for (final s in _photoSlots()) ...(_photos[s.$1] ?? const <String>[]),
      ];

  List<String> get _allLabels => [
        for (final s in _photoSlots())
          for (final _ in _photos[s.$1] ?? const <String>[]) s.$2,
      ];

  Future<void> _goPreview() async {
    _saveTimer?.cancel();
    await _saveDraft();
    if (!mounted) return;
    // 선번·중심국: 글과 사진이 둘 다 있어야 — 빠진 곳이 있으면 먼저 알려줌
    final miss = m.sunMissing();
    if (miss.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('선번 · 중심국을 확인하세요'),
          content: SingleChildScrollView(
            child: Text('선번 글과 사진이 둘 다 있어야 해요.\n\n${miss.map((x) => '• $x').join('\n')}'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('그래도 미리보기')),
            ElevatedButton(onPressed: () => Navigator.pop(c, false), child: const Text('돌아가서 입력')),
          ],
        ),
      );
      if (!mounted) return;
      if (go == false) {
        final first = m.sunFirstMissing();
        if (first != null) _jumpTo(first);
        return;
      }
      if (go != true) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyPreviewScreen(
          station: m.names.isNotEmpty ? m.names.first : widget.station,
          body: m.buildBody(),
          photos: _allPhotos,
          photoLabels: _allLabels,
          // 겹친 사진 표시 (미리보기 첨부 사진에도)
          photoNotes: [for (final p in _allPhotos) _dupNote[p] ?? ''],
          draftId: '',
          kind: '개통',
          onCompleted: _onCompleted,
          // 미리보기에서 뺀 사진은 입력 화면 목록에서도 뺌
          onRemovePhoto: (path) {
            for (final l in _photos.values) {
              l.remove(path);
            }
            _changed();
          },
        ),
      ),
    );
  }

  // 밴드 등록 완료 → 임시저장 삭제 + 새로 입력/수정한 국사정보는 통합국으로
  void _onCompleted() {
    _saveTimer?.cancel();
    final c = m.centerToSave();
    final fk = m.keyOf('floors');
    final isNew = fk == null || m.v('$fk.src').isEmpty;
    if (c != null && (isNew || widget.canEditCenter)) CenterService.saveFloor(c[0], c[1]).catchError((_) {});
    GaetongDraftStore.remove(_draftId);
    // 최근 작성 목록에 남김 (입력 내용 + 사진, ${GaetongRecentStore.keepDays}일 보관)
    //   → 국소명만 바꿔 새로 쓰기 / 사진까지 그대로 다시 열어 고쳐서 다시 올리기
    GaetongRecentStore.add(GaetongDraft(
      station: widget.station.trim(),
      tplName: widget.tpl.name,
      values: Map.of(m.values),
      photos: _photos.map((k, v) => MapEntry(k, List.of(v))),
      savedAt: DateTime.now(),
    ));
  }

  // ---------------- 사진 ----------------
  /// stamp: 사진 위쪽에 새길 글자 (갤러리 저장본에 새김, 밴드에 올릴 때도 새김)
  Future<void> _takePhotos(String key, String label, {String stamp = ''}) async {
    final list = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyCameraScreen(
          station: m.names.isNotEmpty ? m.names.first : widget.station,
          baseName: stamp.isEmpty ? '${widget.tpl.name}_개통' : '${widget.tpl.name}_$stamp',
          label: '${widget.tpl.name} · $label',
          startNumber: (_photos[key]?.length ?? 0) + 1,
          rootFolder: 'F2개통',
          stamp: stamp.isEmpty ? null : stamp,
        ),
      ),
    );
    if (list == null || list.isEmpty || !mounted) return;
    (_photos[key] ??= []).addAll(list);
    _changed();
  }

  Future<void> _pickPhotos(String key, [String stamp = '']) async {
    try {
      final paths = await SurveyPhotoService.pickFromGallery(m.names.isNotEmpty ? m.names.first : widget.station);
      if (paths.isEmpty || !mounted) return;
      final add = await _checkDuplicates(key, paths);
      if (add == null || add.isEmpty || !mounted) return;
      final before = _photos[key]?.length ?? 0;
      final have = await _sigsExcept(add);
      (_photos[key] ??= []).addAll(add);
      _changed();
      await _copyToFolder(add, have, stamp.isEmpty ? '${widget.tpl.name}_개통' : '${widget.tpl.name}_$stamp', before + 1, stamp);
    } catch (e) {
      if (mounted) _toast(context, '사진 선택 오류: $e');
    }
  }

  // 지금 칸들에 들어 있는 사진들의 지문 (새로 고른 것 빼고) — 이미 폴더에 복사된 사진은 또 복사 안 하려고
  Future<Set<String>> _sigsExcept(List<String> add) async {
    final out = <String>{};
    for (final l in _photos.values) {
      for (final p in l) {
        if (add.contains(p)) continue;
        final g = await _sig(p);
        if (g.isNotEmpty) out.add(g);
      }
    }
    return out;
  }

  // 갤러리에서 고른 사진을 국소명 폴더(DCIM/F2개통/<국소명>/)에 한 장 더 저장 (원본은 그대로)
  //   카메라 사진과 같은 이름 규칙, stamp 가 있으면 위쪽에 항목 이름 띠
  Future<void> _copyToFolder(List<String> add, Set<String> have, String baseName, int firstNo, String stamp) async {
    final station = m.names.isNotEmpty ? m.names.first : widget.station;
    var no = firstNo, copied = 0, skipped = 0, failed = 0;
    for (final p in add) {
      final n = no++;
      final g = await _sig(p);
      if (g.isNotEmpty && !have.add(g)) {
        skipped++; // 이미 다른 칸에 넣어서 폴더에 있는 사진
        continue;
      }
      final err = await SurveyPhotoService.copyToAlbum(
          path: p, station: station, baseName: baseName, number: n, folder: 'F2개통', stamp: stamp.isEmpty ? null : stamp);
      if (err == null) {
        copied++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    final folder = SurveyPhotoService.safeName(station);
    _toast(
        context,
        failed > 0
            ? '국소명 폴더 복사 $copied장 · 실패 $failed장 (사진은 앱에 들어갔어요)'
            : copied > 0
                ? '갤러리 F2개통/$folder 폴더에 $copied장 복사했어요${skipped > 0 ? ' (이미 있는 $skipped장 제외)' : ''}'
                : '이미 국소명 폴더에 있는 사진이에요');
  }

  // ---------------- 갤러리 중복 확인 ----------------
  // 갤러리에서 고른 사진이 이미 이 칸이나 다른 칸에 있으면 알려주고, 그래도 넣을지 물어봄
  //  같은 사진 판단: 파일 크기 + 앞·뒤 일부 내용 (또는 같은 원래 파일 이름)
  final Map<String, String> _sigCache = {};

  Future<String> _sig(String path) async {
    final hit = _sigCache[path];
    if (hit != null) return hit;
    var out = '';
    try {
      final f = File(path);
      final len = await f.length();
      final raf = await f.open();
      const n = 16384;
      final head = await raf.read(len < n ? len : n);
      var tail = <int>[];
      if (len > n * 2) {
        await raf.setPosition(len - n);
        tail = await raf.read(n);
      }
      await raf.close();
      var h = 0x811c9dc5;
      for (final b in [...head, ...tail]) {
        h ^= b;
        h = (h * 0x01000193) & 0xffffffff;
      }
      out = '$len-$h';
    } catch (_) {}
    _sigCache[path] = out;
    return out;
  }

  /// 원래 파일 이름 (갤러리에서 가져올 때 붙인 'gallery_' 와 같은 이름 피하려 붙인 숫자는 뺌)
  String _origName(String path) {
    var n = path.split('/').last;
    if (n.startsWith('gallery_')) n = n.substring(8);
    return n.replaceAll(RegExp(r'_\d{13}(?=\.[^.]+$)'), '');
  }

  /// 사진 칸 이름 (알림에 보여줄 것)
  String _slotName(String key) {
    if (key == _sensingKey) return '센싱';
    for (final s in _photoSlots()) {
      if (s.$1 == key) {
        if (s.$2.isNotEmpty) return s.$2;
        break;
      }
    }
    for (final x in m.items) {
      if (x.key == key) return x.it.label;
    }
    return '다른 칸';
  }

  /// 고른 사진 중 이미 있는 것 확인 → 넣을 사진 목록 (null = 취소)
  Future<List<String>?> _checkDuplicates(String key, List<String> picked) async {
    final dupAt = <String, String>{}; // 고른 사진 → 이미 있는 칸
    final existing = <(String, String)>[for (final e in _photos.entries) for (final p in e.value) (e.key, p)];
    for (final p in picked) {
      final sig = await _sig(p), name = _origName(p);
      for (final ex in existing) {
        if (ex.$2 == p) continue;
        if ((sig.isNotEmpty && sig == await _sig(ex.$2)) || name == _origName(ex.$2)) {
          dupAt[p] = ex.$1;
          break;
        }
      }
    }
    if (dupAt.isEmpty || !mounted) return picked;
    final count = <String, int>{};
    for (final k in dupAt.values) {
      count[k] = (count[k] ?? 0) + 1;
    }
    final lines = [
      for (final e in count.entries) '• ${e.key == key ? '이 칸 (${_slotName(key)})' : _slotName(e.key)} : ${e.value}장',
    ];
    final fresh = picked.where((p) => !dupAt.containsKey(p)).toList();
    final c = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('이미 넣은 사진 ${dupAt.length}장이 있어요'),
        content: Text('고른 ${picked.length}장 중 ${dupAt.length}장은 이미 아래 칸에 들어 있어요.\n\n${lines.join('\n')}\n\n그래도 추가할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, 'all'), child: const Text('그래도 모두 추가')),
          if (fresh.isNotEmpty)
            ElevatedButton(onPressed: () => Navigator.pop(c, 'fresh'), child: Text('겹치는 것 빼고 ${fresh.length}장 추가')),
        ],
      ),
    );
    final add = c == 'all' ? picked : (c == 'fresh' ? fresh : <String>[]);
    // 안 넣는 사진은 앱 안 사본 정리
    for (final p in picked.where((x) => !add.contains(x))) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    return c == null || c == 'cancel' ? null : add;
  }

  // 작은 사진을 누르면 크게 보기 (좌우로 넘기기 · 확대 · 빼기) — 실사·밴드 미리보기와 같은 화면
  void _viewPhoto(String key, int idx) {
    final list = _photos[key];
    if (list == null || list.isEmpty) return;
    PhotoViewerPage.open(
      context,
      photos: list,
      start: idx,
      title: _slotName(key),
      noteOf: (i) => i < list.length ? (_dupNote[list[i]] ?? '') : '',
      removeMessage: '이 칸의 사진 목록에서 빠지고, 밴드에도 안 올라가요.\n(휴대폰 갤러리에 저장된 사진은 그대로예요)',
      onRemove: (i) {
        list.removeAt(i);
        _changed();
      },
    );
  }


  // 카메라·갤러리 버튼 (장수 표시 없이 — 넣은 사진은 바로 아래 작은 사진으로 보임)
  Widget _photoBtns(String key, String stamp, {bool compact = false}) {
    if (compact) {
      // 칸 제목 아래 오른쪽 빈자리에 들어가는 작은 버튼
      Widget ib(IconData ic, String tip, VoidCallback f) => SizedBox(
            width: 36,
            height: 32,
            child: IconButton(padding: EdgeInsets.zero, iconSize: 21, tooltip: tip, icon: Icon(ic, color: _indigo), onPressed: f),
          );
      return Row(mainAxisSize: MainAxisSize.min, children: [
        ib(Icons.photo_camera_outlined, '카메라 촬영', () => _takePhotos(key, stamp, stamp: stamp)),
        ib(Icons.photo_library_outlined, '갤러리에서 선택', () => _pickPhotos(key, stamp)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '카메라 촬영',
          icon: const Icon(Icons.photo_camera_outlined, color: _indigo),
          onPressed: () => _takePhotos(key, stamp, stamp: stamp)),
      IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '갤러리에서 선택',
          icon: const Icon(Icons.photo_library_outlined, color: _indigo),
          onPressed: () => _pickPhotos(key, stamp)),
    ]);
  }

  // 센싱: 사진 칸 맨 위 (현장 사진 위) · 갤러리 버튼만 (다른 갤러리 버튼과 같은 화면)
  //   사진 위 글자 없음, 밴드에는 본문 다음 맨 먼저
  Widget _sensingBox() {
    final list = _photos[_sensingKey] ?? const <String>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE0E8)), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Row(children: [
          Icon(Icons.circle, size: 8, color: list.isNotEmpty ? const Color(0xFF2E7D32) : const Color(0xFFB0B4C0)),
          const SizedBox(width: 6),
          const Expanded(child: Text('센싱', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          IconButton(
            tooltip: '갤러리에서 선택',
            icon: const Icon(Icons.photo_library_outlined, color: _indigo),
            onPressed: _pickSensing,
          ),
        ]),
        if (list.isNotEmpty) _thumbs(_sensingKey),
      ]),
    );
  }

  Future<void> _pickSensing() async {
    try {
      final paths = await SurveyPhotoService.pickFromGallery(m.names.isNotEmpty ? m.names.first : widget.station);
      if (paths.isEmpty || !mounted) return;
      final add = await _checkDuplicates(_sensingKey, paths);
      if (add == null || add.isEmpty || !mounted) return;
      final before = _photos[_sensingKey]?.length ?? 0;
      final have = await _sigsExcept(add);
      (_photos[_sensingKey] ??= []).addAll(add);
      _changed();
      await _copyToFolder(add, have, '${widget.tpl.name}_센싱', before + 1, ''); // 센싱은 글자 없이
    } catch (e) {
      if (mounted) _toast(context, '사진 선택 오류: $e');
    }
  }

  // 찍은 사진 작은 그림 (누르면 크게 보기 / 목록에서 빼기)
  Widget _thumbs(String key) {
    final list = _photos[key] ?? const <String>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final note = _dupNote[list[i]];
          final col = note == null ? null : (note == '중복' ? const Color(0xFFD32F2F) : const Color(0xFFEF6C00));
          return GestureDetector(
            onTap: () => _viewPhoto(key, i),
            child: Container(
              width: 60,
              height: 60,
              decoration: col == null ? null : BoxDecoration(border: Border.all(color: col, width: 3), borderRadius: BorderRadius.circular(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(list[i]), fit: BoxFit.cover, cacheWidth: 160),
                  // 겹친 사진 표시: 다른 칸에도 있으면 주황, 같은 칸에 두 번이면 빨강
                  if (note != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: col!.withValues(alpha: 0.85),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        child: Text(note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1.1)),
                      ),
                    ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- 작은 부품 ----------------
  Widget _chip(String label, bool sel, VoidCallback? onTap,
      {bool rect = false, bool disabled = false, bool join = false, bool primary = false}) {
    Color bg = sel ? const Color(0xFFE8EAF6) : Colors.white;
    Color fg = sel ? _indigoDark : const Color(0xFF2B2F3A);
    Color bd = sel ? _indigo : const Color(0xFFB8BCCB);
    if (join && sel) {
      bg = const Color(0xFFE0F2F1);
      fg = const Color(0xFF00594F);
      bd = const Color(0xFF00796B);
    }
    if (primary) {
      bg = _indigo;
      fg = Colors.white;
      bd = _indigo;
    }
    return Opacity(
      opacity: disabled ? 0.35 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rect ? 8 : 22),
          side: BorderSide(color: bd, width: 1, style: BorderStyle.solid),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(rect ? 8 : 22),
          onTap: onTap,
          // 버튼 크기는 글자 길이만큼 (예전에는 한 줄 전체로 늘어나던 문제 수정)
          child: Container(
            height: primary ? 44 : 40,
            constraints: const BoxConstraints(minWidth: 40),
            padding: EdgeInsets.symmetric(horizontal: primary ? 18 : 12),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: primary ? 15 : 14,
                    fontWeight: sel || primary ? FontWeight.bold : FontWeight.w500,
                    color: fg,
                    decoration: disabled ? TextDecoration.lineThrough : null,
                  )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _txt(String t, [String kind = '']) {
    switch (kind) {
      case 'head':
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _indigoDark)),
        );
      case 'hint':
        return Text(t, style: const TextStyle(fontSize: 12, color: _sub));
      case 'badge':
      case 'ok':
      case 'info':
      case 'warn':
        final c = {
          'badge': [const Color(0xFFF3E5F5), const Color(0xFF4A148C)],
          'ok': [const Color(0xFFE8F5E9), const Color(0xFF1B5E20)],
          'info': [const Color(0xFFE8EAF6), const Color(0xFF1A237E)],
          'warn': [const Color(0xFFFFF3E0), const Color(0xFFBF360C)],
        }[kind]!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: TextStyle(fontSize: kind == 'badge' ? 14 : 13, fontWeight: kind == 'badge' ? FontWeight.bold : FontWeight.normal, color: c[1])),
        );
      default:
        return Text(t, style: const TextStyle(fontSize: 15, color: _ink));
    }
  }

  // 줄바꿈 (Wrap 안에서 다음 줄로)
  Widget _br() => const SizedBox(width: double.infinity, height: 0);

  Widget _inp(String key, String hint, {double? width, bool numeric = false, String? display, ValueChanged<String>? onChanged}) {
    final w = _SyncInput(
      key: ValueKey('in:$key'),
      value: display ?? m.val(key),
      hint: hint,
      numeric: numeric,
      center: width != null,
      onChanged: onChanged ?? (s) => m.setVal(key, numeric ? s.replaceAll(RegExp(r'[^0-9.]'), '') : s),
    );
    return width != null ? SizedBox(width: width, child: w) : ConstrainedBox(constraints: const BoxConstraints(minWidth: 140, maxWidth: 320), child: w);
  }

  List<Widget> _chipsFor(String k, List<String> opts) =>
      [for (final op in opts) _chip(op, m.val(k) == op, () => m.setVal(k, m.val(k) == op ? '' : op))];

  Widget _row(List<Widget> ctrls, {String? title, VoidCallback? onRemove, bool done = false, Color? bg, Color? border, Widget? trailing}) {
    final wrap = Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: ctrls);
    if (title == null && bg == null) return wrap;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      decoration: BoxDecoration(
        color: done ? _doneBg : (bg ?? Colors.white),
        border: Border.all(color: done ? _doneBorder : (border ?? const Color(0xFFDDE0E8))),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          SizedBox(
            height: 42,
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _teal))),
              if (trailing != null) trailing,
              if (onRemove != null)
                IconButton(
                  tooltip: '$title 빼기',
                  icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFC62828)),
                  onPressed: onRemove,
                ),
            ]),
          ),
        if (title == null) const SizedBox(height: 6),
        wrap,
      ]),
    );
  }

  // ---------------- 복잡한 항목 (줄 안에 버튼/입력칸) ----------------
  _RF _rows(GItem it, String key) {
    final tpl = widget.tpl;
    final u = tpl.unit;
    final units = m.units();
    final rf = _RF();
    VoidCallback? unitRm(int n) => units.length > 1 ? () => m.removeUnit(n) : null;
    final nextU = [1, 2, 3, 4].where((x) => !units.contains(x)).toList();
    void unitAdd() {
      if (nextU.isNotEmpty) {
        rf.addLabel = '${u}_${nextU.first} 추가';
        rf.onAdd = () => m.addUnit();
      }
    }

    List<String> nums(int a, int b) => [for (var i = a; i <= b; i++) '$i'];

    switch (it.type) {
      case 'bldg': {
        // 건물 전체층 / 설치층 : 층 버튼 + 기타 직접 입력
        Widget floors(String s, String title, List<String> opts) {
          final k = '$key.$s', cur = m.v(k);
          return _row([
            for (final op in opts) _chip(op, cur == op, () => m.setVals({k: cur == op ? '' : op, '${k}e': ''})),
            if (cur == '기타') ...[_inp('${k}e', '예: 15', width: 70, numeric: true), _txt('층')],
          ], title: title, done: cur.isNotEmpty);
        }

        rf.rows.add(floors('all', '건물 전체층', ['1층', '2층', '3층', '4층', '5층', '기타']));
        rf.rows.add(floors('at', '설치층', ['B1층', '1층', '2층', '3층', '4층', '5층', '기타']));
        rf.preview = m.out(it, key).join('\n');
        break;
      }

      case 'qtyNu': {
        final nu = m.v('$key.nu').isNotEmpty;
        rf.rows.add(_row([
          if (!nu) ...[
            _inp(key, '수량', width: 64, numeric: true, display: m.val(key).replaceAll(RegExp(r'EA$', caseSensitive: false), '')),
            _txt('EA'),
          ],
          _chip('미사용', nu, () => m.setVals({'$key.nu': nu ? '' : '1', key: ''})),
        ]));
        break;
      }

      case 'duMats': {
        // 사용 자재를 먼저 고르면 고른 것마다 입력칸 (수량 기본 1, 구간 기본 문구 자동)
        final presets = m.duPresets(), sel = m.duSel(key);
        final top = <Widget>[_txt('자재 선택 (여러 개)', 'head'), _br()];
        for (var i = 0; i < presets.length; i++) {
          final id = 'p$i', on = sel.contains(id);
          top.add(_chip(presets[i].name, on, () => m.duToggle(key, id, !on)));
        }
        final etcs = sel.where((x) => x.startsWith('etc')).toList();
        if (etcs.length < 8) {
          final nx = etcs.fold<int>(0, (a, x) => (int.tryParse(x.substring(3)) ?? 0) > a ? int.parse(x.substring(3)) : a) + 1;
          top.add(_chip('+ 기타', false, () => m.duToggle(key, 'etc$nx', true)));
        }
        rf.rows.add(_row(top));
        var etcNo = 0;
        for (final en in m.duEntries(key)) {
          final p = en.p, pr = en.pr;
          final nu = m.v('${p}nu').isNotEmpty;
          Widget nuChip() => _chip('미사용', nu, () => m.setVal('${p}nu', nu ? '' : '1'));
          final c = <Widget>[];
          if (nu) {
            c.add(nuChip());
          } else {
            if (pr == null) c.addAll([_inp('${p}nm', '자재 이름 (예: GPS 4WAY분배기)'), _br()]);
            if (pr != null && pr.kinds.isNotEmpty) {
              final k = m.v('${p}k');
              for (final op in pr.kinds) {
                c.add(_chip(op, k == op, () => m.setVals({'${p}k': k == op ? '' : op, '${p}sb': ''}), rect: true));
              }
              if (pr.nu) c.add(nuChip());
              if (pr.subs.isNotEmpty && k.isNotEmpty) c.addAll([_br(), _txt(k, 'head'), ..._chipsFor('${p}sb', pr.subs[k] ?? const [])]);
              c.add(_br());
            } else if (pr != null && pr.nu) {
              c.addAll([nuChip(), _br()]);
            }
            if (pr == null || pr.len) c.addAll([_inp('${p}len', '길이', width: 56, numeric: true), _txt('M')]);
            c.addAll([_txt('×', 'head'), _inp('${p}q', '1', width: 48, numeric: true), _txt('EA')]);
            if (pr != null && pr.real) c.addAll([_txt('실거리', 'head'), _inp('${p}r', '실거리', width: 60, numeric: true), _txt('M')]);
            if (pr?.fixedSec != null) {
              final fs = pr!.fixedSec!.replaceAll(RegExp(r'\s*~\s*'), '~');
              c.add(_txt('[$fs]', 'hint'));
            } else if (pr == null || pr.sec != null) {
              c.addAll([_br(), _txt('구간', 'head'), _inp('${p}ut', '예: DU ~ DDF (비워도 됨)')]);
            }
          }
          final title = pr == null ? '기타 ${++etcNo}' : pr.name;
          rf.rows.add(_row(c, title: title, onRemove: () => m.duToggle(key, en.id, false), done: m.duEntryDone(en)));
        }
        if (sel.isEmpty) rf.rows.add(_txt('위에서 자재를 고르면 입력칸이 생겨요', 'hint'));
        rf.note = '밴드에는 아래 특이사항 칸 내용과 함께 "특이사항&자재내역"으로 올라가요';
        rf.preview = m.duLines(key).join('\n');
        break;
      }

      case 'chips': {
        final toks = m.v(key).split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
        rf.rows.add(_row([
          for (final op in it.opts)
            _chip(op, toks.contains(op), () {
              final now = m.v(key).split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
              m.setVal(key, (toks.contains(op) ? now.where((x) => x != op) : [...now, op]).join(' '));
            }),
        ]));
        break;
      }

      case 'tray': {
        rf.rows.add(_row([_txt('케이블정리대', 'head'), _inp('$key.q', '수량', width: 56, numeric: true), _txt('EA'), _txt('비우면 밴드에서 빠져요', 'hint')]));
        rf.preview = m.linesFrom(it.id).join('');
        break;
      }

      case 'module': {
        final cnt = m.modCount(key);
        final short = it.label.replaceAll('광공유모듈', '');
        if (it.fold && m.v('$key.open').isEmpty) {
          final cur = m.modAll(key);
          rf.rows.add(_row([cur.isNotEmpty ? _txt(cur, 'badge') : _txt('선택 안 함', 'hint'), _chip('펼쳐서 선택', false, () => m.setVal('$key.open', '1'))]));
          break;
        }
        for (var e = 1; e <= cnt; e++) {
          final mk = m.modKey(key, e);
          final b = m.v(mk);
          final c = <Widget>[
            for (final op in it.opts) _chip(op, b == op, () => m.setVals({mk: b == op ? '' : op, '$mk.sub': '', '$mk.etc': ''})),
          ];
          if (b == 'OCM') {
            c.addAll([_br(), _txt('OCM 종류', 'head'), ..._chipsFor('$mk.sub', ['L4', 'L4R', 'L5', 'L5R', 'L6', 'L6R', 'E35', 'PS5', '기타'])]);
            if (m.v('$mk.sub') == '기타') c.addAll([_br(), _txt('OCM-'), _inp('$mk.etc', '뒤에 붙을 내용')]);
          }
          if (b == 'PON') c.addAll([_br(), _txt('PON 종류', 'head'), ..._chipsFor('$mk.sub', ['2.0', '3.1'])]);
          final last = e == cnt && cnt > 1;
          rf.rows.add(cnt > 1
              ? _row(c, title: '$short $e', onRemove: last ? () => m.setVals({'$key.n': '', mk: '', '$mk.sub': '', '$mk.etc': ''}) : null)
              : _row(c));
        }
        if (cnt < 2) {
          rf.addLabel = '$short 광공유모듈 추가 (2개째)';
          rf.onAdd = () => m.setVal('$key.n', '2');
        }
        if (it.fold) rf.rows.add(_row([_chip('접기', true, () => m.setVal('$key.open', ''))]));
        if (m.modAll(key).isNotEmpty) rf.preview = '→ ${m.modAll(key)}';
        break;
      }

      case 'mats': {
        _matsRows(it, key, rf);
        break;
      }

      case 'att': {
        final k = m.attKind();
        if (k == null && tpl.tech == '4G') {
          rf.hidden = true;
          break;
        }
        if (k == null) {
          rf.rows.add(_row([_txt('광공유모듈(S-MUX·PON·C-MUX·L-MUX)을 고르면 나타나요', 'warn')]));
        } else {
          final cnt = m.attCount(key);
          for (var e = 1; e <= cnt; e++) {
            final p = '$key.$e.';
            final cur = m.v('${p}v');
            final c = <Widget>[_txt(k.name, 'badge')];
            if (cur.isNotEmpty && k.opts.contains(cur)) {
              c.addAll([
                _chip('${cur}dB', true, () => m.setVal('${p}v', '')),
                _txt('수량', 'head'),
                _inp('${p}q', '수량', width: 52, numeric: true, display: m.val('${p}q').isEmpty ? '1' : m.val('${p}q')),
                _txt('EA'),
              ]);
            } else {
              c.addAll([for (final op in k.opts) _chip(op, false, () => m.setVal('${p}v', op)), _txt('dB')]);
            }
            final last = k.multi && e == cnt && cnt > 1;
            rf.rows.add(k.multi && cnt > 1
                ? _row(c, title: '개별ATT $e', onRemove: last ? () => m.setVals({'$key.n': '${cnt - 1}', '${p}v': '', '${p}q': ''}) : null)
                : _row(c));
          }
          if (k.multi && cnt < 8) {
            rf.addLabel = '개별ATT 추가';
            rf.onAdd = () => m.setVal('$key.n', '${cnt + 1}');
          }
        }
        rf.preview = m.attLines(key).join('\n');
        break;
      }

      case 'floors': {
        _floorRows(it, key, rf);
        break;
      }

      case 'sfpMulti': {
        final sel = m.sfpMultiSel(key);
        final ids = [for (var i = 0; i < it.opts.length; i++) '$i', 'e'];
        String name(String id) => id == 'e' ? '기타' : it.opts[int.parse(id)];
        rf.rows.add(_row([
          _txt('여러 개 선택', 'hint'),
          _br(),
          for (final id in ids)
            _chip(name(id), sel.contains(id),
                () => m.setVal('$key.sel', (sel.contains(id) ? sel.where((x) => x != id) : [...sel, id]).join(','))),
        ]));
        for (final id in ids.where(sel.contains)) {
          rf.rows.add(_row([
            id == 'e' ? _inp('$key.etc', '기타 SFP 이름') : _txt(name(id), 'badge'),
            _txt('수량', 'head'),
            _inp('$key.$id.q', '수량', width: 56, numeric: true, display: m.val('$key.$id.q').isEmpty ? '1' : m.val('$key.$id.q')),
            _txt('SET'),
          ]));
        }
        rf.preview = m.sfpMultiFmt(it, key);
        break;
      }

      case 'pick': {
        rf.rows.add(_row([
          ..._chipsFor(key, [...it.opts, '기타']),
          if (m.v(key) == '기타') ...[_br(), _inp('$key.etc', '기타 내용 입력')],
        ]));
        rf.preview = m.pickFmt(key);
        break;
      }

      case 'alarm1': {
        final on = m.v('$key.o').isNotEmpty;
        final ex = m.v('$key.ex').isNotEmpty; // 기존활용 (고르면 입력 완료)
        final nu = m.v('$key.nu').isNotEmpty; // 미사용 (고르면 입력 완료)
        final plain = !on && !ex && !nu;
        // 기타·기존활용·미사용은 셋 중 하나만
        void pick(String k, bool cur) => m.setVals({'$key.o': '', '$key.ex': '', '$key.nu': '', '$key.$k': cur ? '' : '1'});
        rf.rows.add(_row([
          if (plain) ...[_inp('$key.len', '길이', width: 64, numeric: true), _txt('M'), _txt('×', 'head'), ..._chipsFor('$key.q', ['1', '2', '3'])],
          if (plain) _br(),
          _chip('기타', on, () => pick('o', on)),
          _chip('기존활용', ex, () => pick('ex', ex)),
          _chip('미사용', nu, () => pick('nu', nu)),
          if (on) ...[_br(), _inp('$key.etc', '예: 신형800 전용1')],
        ]));
        rf.note = '수량을 안 고르면 1개로 표시돼요';
        rf.preview = m.out(it, key).join('\n');
        break;
      }

      case 'mother': {
        final k = '$key.r';
        final q = m.v('$key.c');
        final cs = <Widget>[
          _txt('중심국', 'head'),
          _inp('$key.c', '예: 목동 → S목동오목교중심국', onChanged: (s) => m.applyCenter(s)),
        ];
        final exact = m.centers.any((x) => x.name == q);
        if (q.isNotEmpty && !exact) {
          // 실사 국소명과 같은 방식: 띄어쓰기·대소문자 무시, 앞부분 일치 먼저, 최대 8개 목록
          String norm(String x) => x.replaceAll(RegExp(r'\s+'), '').toLowerCase();
          final nq = norm(q);
          final ms = m.centers.where((x) => norm(x.name).contains(nq)).toList()
            ..sort((a, b) {
              final pa = norm(a.name).startsWith(nq) ? 0 : 1, pb = norm(b.name).startsWith(nq) ? 0 : 1;
              return pa != pb ? pa - pb : a.name.compareTo(b.name);
            });
          cs.add(_br());
          if (ms.isNotEmpty) {
            cs.add(Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFC5CAE9)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                for (final x in ms.take(8))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_city, size: 20, color: _indigo),
                    title: Text(x.name, style: const TextStyle(fontSize: 15)),
                    subtitle: x.floor.isNotEmpty ? const Text('국사정보 있음', style: TextStyle(fontSize: 11, color: _teal)) : null,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      m.applyCenter(x.name);
                    },
                  ),
              ]),
            ));
          } else {
            cs.add(_txt(m.centers.isEmpty ? '통합국 목록을 아직 못 받았어요 (인터넷 확인)' : '통합국 목록에 없는 이름이에요 · 개통 완료 때 새로 추가돼요', 'hint'));
          }
        }
        cs.addAll([
          _br(),
          _txt('RT', 'head'),
          _inp(k, 'RT 이름', width: 150),
          _chip('직결', m.v(k) == '직결', () => m.setVal(k, m.v(k) == '직결' ? '' : '직결')),
        ]);
        rf.rows.add(_row(cs));
        rf.preview = m.motherFmt(key);
        break;
      }

      case 'mux': {
        String k(String s) => '$key.$s';
        rf.rows.add(_row([
          _txt('R'), _inp(k('a'), '열', width: 54, numeric: true), _txt('-'), _inp(k('b'), '위치', width: 54, numeric: true),
          _txt('_S-MUX#'), _inp(k('c'), '랙', width: 54, numeric: true), _br(),
          _txt('_Shelf'), _inp(k('d'), '셀프', width: 54, numeric: true), _txt('-'), _inp(k('e'), '슬롯', width: 54, numeric: true),
          _chip('(배면)', m.v(k('bk')).isNotEmpty, () => m.setVal(k('bk'), m.v(k('bk')).isNotEmpty ? '' : '1')),
          _br(),
          // 만들어 둔 셀프 위치 글을 붙여 넣는 칸 (넣으면 위 칸 대신 이 글이 올라감)
          SizedBox(
            width: double.infinity,
            child: _SyncInput(
                key: ValueKey('in:${k('txt')}'),
                value: m.val(k('txt')),
                hint: '또는 붙여넣기 (예: R7-5_S-MUX#3_Shelf6-2)',
                onChanged: (s) => m.setVal(k('txt'), s)),
          ),
        ]));
        rf.note = m.v(k('txt')).isNotEmpty ? '붙여 넣은 글이 그대로 밴드에 올라가요' : 'R칸을 비우면 S-MUX#부터 표시돼요';
        rf.preview = m.muxFmt(key);
        break;
      }

      case 'units': {
        rf.rows.add(_row([
          for (final n in [1, 2, 3, 4])
            _chip('${u}_$n', units.contains(n), () => units.contains(n) ? m.removeUnit(n) : m.addUnit(n)),
        ]));
        rf.note = '개통한 장비만 고르세요. SFP·알람·케이블 칸이 같이 늘고 줄며, 밴드에는 고른 것만 올라가요.';
        break;
      }

      case 'sfpU': {
        final mod = m.modBase();
        // 다른 장비에서 이미 고른 SFP 번호는 못 고름
        List<Widget> noChips(int n) {
          final kk = '$key.$n.no';
          return [
            for (final op in nums(1, 8))
              units.any((o) => o != n && m.v('$key.$o.no') == op)
                  ? _chip(op, false, () => _toast(context, '$op번은 이미 다른 ${u}에서 고른 번호예요.'), disabled: true)
                  : _chip(op, m.val(kk) == op, () => m.setVal(kk, m.val(kk) == op ? '' : op)),
          ];
        }
        for (final n in units) {
          final ck = '$key.$n.cc';
          final ccOn = n > 1 && m.v(ck).isNotEmpty;
          rf.rows.add(_row([
            ccOn ? _txt('CC', 'badge') : (mod.isNotEmpty ? _txt(mod, 'badge') : _txt('광공유모듈을 먼저 선택', 'warn')),
            if (it.cc && n > 1) _chip('CC', ccOn, () => m.setVal(ck, ccOn ? '' : '1')),
            // 10G/25G: 첫 번째 장비에서 고른 것이 나머지에도 자동 (바꿀 수 있음)
            for (final op in ['10G', '25G'])
              _chip(op, m.sfpSp(key, n) == op, () => m.setVal('$key.$n.sp', m.v('$key.$n.sp') == op ? '' : op)),
            _br(),
            _txt('번호', 'head'),
            ...noChips(n),
          ], title: 'SFP ${u}_$n', onRemove: unitRm(n), done: m.sfpDone(key, n)));
        }
        unitAdd();
        rf.note = '10G/25G와 번호를 둘 다 골라야 완료 · 첫 번째 장비의 10G/25G가 나머지에도 자동으로 들어가요';
        if (it.cc && units.length > 1) rf.note += '\n2번부터 [CC]를 누르면 모듈 대신 CC로 표시돼요';
        rf.preview = m.out(it, key).join('\n');
        break;
      }

      case 'alarmU': {
        // 먼저 알람케이블을 쓰는 장비 번호를 고르고 (개통 장비 중에서), 고른 것마다 길이 또는 시설팀 포설
        final none = m.alarmNone(key);
        final au = m.alarmUnits(key);
        void toggleUnit(int n) {
          final next = au.contains(n) ? au.where((x) => x != n).toList() : ([...au, n]..sort());
          m.setVals({'$key.sel': next.join(','), '$key.none': ''});
        }
        rf.rows.add(_row([
          _txt('사용 장비', 'head'),
          for (final n in units) _chip('${u}_$n', !none && au.contains(n), () => toggleUnit(n)),
          _chip('미사용', none, () => m.setVals({'$key.none': none ? '' : '1', '$key.sel': ''})),
        ]));
        if (!none) {
          for (final n in au) {
            final p = '$key.$n.';
            rf.rows.add(_row([
              _inp('${p}len', '길이', width: 64, numeric: true),
              _txt('M'),
              _chip('시설팀 포설', m.v('${p}fac').isNotEmpty, () => m.setVal('${p}fac', m.v('${p}fac').isNotEmpty ? '' : '1')),
            ], title: '${u}_$n', onRemove: () => toggleUnit(n), done: m.alarmVal(key, n).isNotEmpty));
          }
          if (au.isEmpty) rf.rows.add(_txt('알람케이블을 쓰는 ${u}를 먼저 고르세요 (개통 $u에서 고른 장비만 나와요)', 'hint'));
        }
        rf.preview = m.out(it, key).join('\n');
        break;
      }

      case 'cableU': {
        final auto = m.autoSpec();
        for (final n in units) {
          final p = '$key.$n.';
          final cur = m.v('${p}spec').isNotEmpty ? m.v('${p}spec') : auto;
          rf.rows.add(_row([
            for (final sp in ['5G 2C SC/APC-LC/PC', '5G 2C LC/PC-LC/PC']) _chip(sp, cur == sp, () => m.setVal('${p}spec', sp == auto ? '' : sp)),
            _br(),
            _inp('${p}len', '길이', width: 56, numeric: true), _txt('M'),
            _txt('실거리', 'head'), _inp('${p}real', '실거리', width: 56, numeric: true), _txt('M'),
            _chip('시설팀 포설', m.v('${p}fac').isNotEmpty, () => m.setVal('${p}fac', m.v('${p}fac').isNotEmpty ? '' : '1')),
          ], title: '${u}_$n', onRemove: unitRm(n), done: m.cableVal(key, n).isNotEmpty));
        }
        unitAdd();
        rf.note = auto.isNotEmpty ? '규격은 광공유모듈(${m.modBase()})에 맞춰 자동 선택돼요' : '광공유모듈을 고르면 규격이 자동 선택돼요';
        rf.preview = m.out(it, key).join('\n');
        break;
      }

      case 'link': {
        final cnt = m.linkCount(key);
        // 모든 정류기의 M·S에서 이미 고른 번호 (기타 제외) → 다른 칸에서는 못 고름
        final used = <MapEntry<String, String>>[];
        for (var j = 1; j <= cnt; j++) {
          for (final s in ['m', 's']) {
            final kk = '$key.$j.$s';
            final x = m.v(kk);
            if (x.isNotEmpty && x != '기타') used.add(MapEntry(kk, x));
          }
        }
        final msOpts = [...(it.msOpts.isNotEmpty ? it.msOpts : nums(1, 4)), '기타'];
        for (var i = 1; i <= cnt; i++) {
          final p = '$key.$i.';
          List<Widget> msChips(String kk) => [
                for (final op in msOpts)
                  (op != '기타' && used.any((x) => x.key != kk && x.value == op))
                      ? _chip(op, false, () => _toast(context, '$op은(는) 이미 다른 곳(M/S 또는 다른 정류기)에서 고른 번호예요.'), disabled: true)
                      : _chip(op, m.val(kk) == op, () => m.setVal(kk, m.val(kk) == op ? '' : op)),
              ];
          final last = i == cnt && cnt > 1;
          rf.rows.add(_row([
            ..._chipsFor('${p}mk', widget.tpl.eq == 'RRU' ? ['동아', 'UNA', 'PCNI', '우리', '에어텍'] : ['동아', 'UNA', 'PCNI']),
            _br(), _txt('M', 'head'), ...msChips('${p}m'),
            if (m.v('${p}m') == '기타') _inp('${p}me', 'M 내용', width: 80),
            _br(), _txt('S', 'head'), ...msChips('${p}s'),
            if (m.v('${p}s') == '기타') _inp('${p}se', '예: 800', width: 80),
            _br(), _txt('배터리', 'head'), ..._chipsFor('${p}bt', ['설치', '미설치']),
            if ((_photos['${p}ph'] ?? const []).isNotEmpty) ...[_br(), _thumbs('${p}ph')],
          ],
              title: '정류기 $i',
              trailing: _photoBtns('${p}ph', '정류기 $i'),
              onRemove: last
                  ? () {
                      _photos.remove('${p}ph');
                      m.setVals({'$key.n': '${cnt - 1}', for (final s in ['mk', 'm', 'me', 's', 'se', 'bt']) '$p$s': ''});
                    }
                  : null,
              done: m.v('${p}mk').isNotEmpty && m.v('${p}bt').isNotEmpty));
        }
        if (cnt < 4) {
          rf.addLabel = '정류기 추가';
          rf.onAdd = () => m.setVal('$key.n', '${cnt + 1}');
        }
        rf.preview = m.out(it, key).join('\n');
        break;
      }

      case 'sunU': {
        final src = m.sunSource(it);
        final entries = src?.entries ?? const <MatEntry>[];
        final where = it.sunFrom == 'rmats' ? '자재내역 · 리모트' : '자재내역 · 중심국';
        if (entries.isEmpty) {
          rf.rows.add(_txt('$where 에서 사용처를 고르면 여기에 선번 입력칸이 생겨요', 'hint'));
          break;
        }
        for (final en in entries) {
          final lab = m.sunLabel(src!.it, en);
          final slots = m.sunSlots(src.it, en, key);
          Widget input(String k) => SizedBox(
                width: double.infinity,
                child: _SyncInput(
                    key: ValueKey('in:$k'),
                    value: m.val(k),
                    hint: '예: R5-2_OFD#1(2F~3F)_S11_57P',
                    focusNow: _flashKey == k && _flashText,
                    onChanged: (s) => m.setVal(k, s)),
              );
          if (slots.length == 1) {
            final k = slots.first.$2;
            rf.rows.add(_flashWrap(k, _row([
              input(k),
              if ((_photos[k] ?? const []).isNotEmpty) _thumbs(k),
            ], title: lab, trailing: _photoBtns(k, _sunStamp(it, lab)), done: m.sunSlotDone(it, k))));
          } else {
            // 층간FDF~사업자OFD 처럼 양쪽 다 선번이 있으면 칸 2개 (각각 사진)
            rf.rows.add(_row([
              for (final sl in slots)
                SizedBox(
                  width: double.infinity,
                  child: _flashWrap(
                    sl.$2,
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(sl.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _indigoDark))),
                        _photoBtns(sl.$2, _sunStamp(it, '$lab (${sl.$1})'), compact: true),
                      ]),
                      input(sl.$2),
                      if ((_photos[sl.$2] ?? const []).isNotEmpty) ...[const SizedBox(height: 6), _thumbs(sl.$2)],
                    ]),
                  ),
                ),
            ], title: lab, done: slots.every((sl) => m.sunSlotDone(it, sl.$2))));
          }
        }
        rf.note = it.sunFrom == 'rmats'
            ? '사진 위쪽에 사용처 이름이 새겨져요 (갤러리 저장본·밴드)'
            : '선번 글과 사진이 둘 다 있어야 완료 · DU·MHS·MUX·판넬 쪽은 선번이 없어서 층간FDF·사업자OFD 쪽만 칸이 생겨요';
        rf.preview = m.sunLines(it, key).join('\n');
        break;
      }

      case 'mhs': {
        rf.rows.add(_row([
          _txt('L9TU', 'head'),
          ..._chipsFor('$key.l9', ['1EA', '2EA', '기타']),
          if (m.v('$key.l9') == '기타') _inp('$key.l9e', '기타 내용', width: 120),
          _br(),
          _txt('MHS', 'head'),
          ..._chipsFor('$key.mhs', ['QMHS', 'IMHS', 'SMHS', 'BR']),
        ]));
        rf.note = 'BR은 밴드에 BR수용 · SMHS는 SMHS CU×1EA, PSU UNIT×1EA로 표기';
        rf.preview = m.out(it, key).join('\n');
        break;
      }
    }
    return rf;
  }

  // 자재 (중심국·리모트 공통): 사용처를 먼저 골라두면 사용처마다 입력칸
  void _matsRows(GItem it, String key, _RF rf) {
    final all = m.matUsages(it);
    final sel = m.matSel(key);
    final lshOn = sel.contains('lsh');

    List<Widget> end(String p, String s) => [
          _txt(s == 'a' ? '한쪽' : '반대쪽', 'head'),
          ..._chipsFor('$p$s', ['SC', 'FC', 'LC']),
          if (m.v('$p$s') == 'LC') ...[
            const Text('/', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _indigo)),
            for (final op in ['PC', 'APC']) _chip(op, m.val('$p${s}p') == op, () => m.setVal('$p${s}p', m.val('$p${s}p') == op ? '' : op), rect: true),
          ],
        ];

    List<Widget> body(String p, Usage u) {
      final c = <Widget>[
        _inp('${p}ut', u.id == 'etc' ? '사용처 직접 입력' : '사용처 문구', display: m.matUsage(it, p, u.id)),
      ];
      // 4G RRU 리모트 기타: 2.6G용 OJC / 800전용OJP (길이·실거리·타입 없이 수량만)
      final kinds = u.id == 'etc' ? m.etcKinds(it) : const <String>[];
      if (kinds.isNotEmpty) {
        final kind = m.v('${p}kind');
        c.addAll([
          _br(),
          for (final k in kinds) _chip(k, kind == k, () => m.setVal('${p}kind', kind == k ? '' : k), rect: true),
        ]);
        if (kind.isNotEmpty) {
          c.addAll([_br(), _txt('수량', 'head'), _inp('${p}q', '1', width: 48, numeric: true), _txt('EA'), _txt('길이·실거리·타입 없이 올라가요', 'hint')]);
          return c;
        }
      }
      // 중심국: 케이블을 그대로 쓰면 [기존활용] → 타입·길이 입력 없이 완료, 밴드에 '기존활용'
      if (!it.remote && m.v('${p}ex').isNotEmpty) {
        c.addAll([_br(), _chip('기존활용', true, () => m.setVal('${p}ex', ''), rect: true), _txt('타입·길이 없이 "기존활용"으로 올라가요', 'hint')]);
        return c;
      }
      final exChip = it.remote ? null : _chip('기존활용', false, () => m.setVal('${p}ex', '1'), rect: true);
      if (u.fixed) {
        c.addAll([_br(), _txt('(파) 2C LC/PC-LC/PC 고정', 'badge'), if (exChip != null) exChip]);
      } else if ((u.def != null || u.rdef) && m.v('${p}edit').isEmpty) {
        final head = m.matHead(p, u);
        c.addAll([
          _br(),
          _txt(head.isEmpty ? '타입 없음' : head, 'badge'),
          _chip('타입 변경', false, () {
            final o = <String, String>{'${p}edit': '1'};
            if (u.rdef && m.v('${p}custom').isEmpty) {
              m.remoteDef().forEach((s, x) => o['$p$s'] = x);
              o['${p}custom'] = '1';
            }
            m.setVals(o);
          }),
          if (exChip != null) exChip,
        ]);
      } else {
        if (u.def != null || u.rdef) c.addAll([_br(), _chip('변경 완료', true, () => m.setVal('${p}edit', ''))]);
        if (exChip != null) c.addAll([if (u.def == null && !u.rdef) _br(), exChip]);
        final colors = it.remote
            ? [['외', '(외)'], ['적외', '(적)(외)'], ['파', '(파)'], ['노', '(노)']]
            : [['파', '파랑 (파)'], ['노', '노랑 (노)'], ['주', '주황 (주)']];
        c.addAll([
          _br(),
          _txt('색', 'head'),
          for (final x in colors) _chip(x[1], m.v('${p}c') == x[0], () => m.setVal('${p}c', m.v('${p}c') == x[0] ? '' : x[0])),
          // 심선 수: 숫자 직접 입력 (예: 2 → 2C, 16 → 16C), 비우면 표시 안 함
          _txt('심선', 'head'),
          _inp('${p}n', '예: 2', width: 52, numeric: true,
              display: m.v('${p}n').replaceAll(RegExp(r'[^0-9]'), ''),
              onChanged: (s) {
                final d = s.replaceAll(RegExp(r'[^0-9]'), '');
                m.setVal('${p}n', d.isEmpty ? '' : '${d}C');
              }),
          _txt('C'),
          _br(), ...end(p, 'a'),
          _br(), ...end(p, 'b'),
          if (m.matType(p).isNotEmpty) ...[_br(), _txt(m.matHead(p, u, ignoreRdef: true), 'badge')],
        ]);
      }
      if (u.qty) {
        // L9TU 쪽은 수량이 많아서 버튼으로 (그 이상은 직접 입력)
        c.addAll([
          _br(), _inp('${p}len', '길이', width: 56, numeric: true), _txt('M'),
          _txt('실거리', 'head'), _inp('${p}r', '실거리', width: 60, numeric: true), _txt('M'),
          _br(), _txt('수량', 'head'), ..._chipsFor('${p}q', ['1', '2', '3', '4', '5', '6']),
          _inp('${p}q', '직접', width: 56, numeric: true), _txt('EA'),
        ]);
      } else {
        c.addAll([
          _br(), _inp('${p}len', '길이', width: 56, numeric: true), _txt('M'), _txt('×', 'head'),
          _inp('${p}q', '1', width: 48, numeric: true), _txt('EA'),
          _txt('실거리', 'head'), _inp('${p}r', '실거리', width: 60, numeric: true), _txt('M'),
        ]);
      }
      return c;
    }

    final top = <Widget>[_txt('사용처 선택 (여러 개)', 'head'), _br()];
    String lastG = '';
    for (final x in all.where((x) => x.id != 'etc' && !(x.id == 'ls' && lshOn))) {
      if (x.grp != null && x.grp != lastG) {
        top.addAll([_br(), _txt(x.grp!, 'head'), _br()]);
        lastG = x.grp!;
      }
      final on = sel.contains(x.id);
      top.add(_chip(x.label, on, () => m.matToggle(it, key, x.id, !on)));
    }
    final etcs = sel.where((x) => x.startsWith('etc')).toList();
    if (lastG.isNotEmpty) top.add(_br());
    if (etcs.length < 5) {
      final nextN = etcs.fold<int>(0, (a, x) => (int.tryParse(x.substring(3)) ?? 0) > a ? int.parse(x.substring(3)) : a) + 1;
      top.add(_chip('+ 기타', false, () => m.matToggle(it, key, 'etc$nextN', true)));
    }
    rf.rows.add(_row(top));
    final ents = m.matEntries(it, key);
    var etcNo = 0;
    for (final en in ents) {
      final u = m.usageOf(it, en.uid)!;
      final title = u.id == 'etc' ? '기타 ${++etcNo}' : u.label;
      rf.rows.add(_row(body(en.p, u), title: title, onRemove: () => m.matToggle(it, key, en.id, false), done: m.matEntryDone(it, en)));
    }
    if (ents.isEmpty) rf.rows.add(_row([_txt('위에서 사용처를 고르면 입력칸이 생겨요', 'hint')]));
    rf.note = it.remote
        ? '사용처를 고르면 기본 타입이 자동으로 들어가요. [타입 변경]으로 바꿀 수 있어요.'
        : '사용처의 층은 국사정보에서 고른 층으로 자동 표시돼요. 문구는 직접 고칠 수 있어요.';
    rf.preview = m.matLines(it, key).join('\n');
  }

  // 국사정보: 층 + JOIN UP/NOC, 통합국 시트와 연결
  void _floorRows(GItem it, String key, _RF rf) {
    final mk = m.keyOf('mother');
    final center = mk != null ? m.v('$mk.c') : '';
    final src = m.v('$key.src'), xl = m.floorExcelLine(key);
    final st = src.isNotEmpty
        ? (xl == src
            ? ['통합국 시트와 같아요 (${m.v('$key.center')})', 'ok']
            : ['불러온 내용과 달라요 · 아래 [국사정보 수정]을 누르면 통합국 F열이 바뀌어요 (개통 완료 때도 자동 저장)', 'info'])
        : center.isNotEmpty
            ? ['처음 입력하는 국사정보예요 · 개통 완료 때 통합국 F열에 저장돼요', 'info']
            : ['모국명에 중심국을 입력하면, 저장된 국사정보는 자동으로 불러와요', 'hint'];
    rf.rows.add(_row([_txt(st[0], st[1])]));

    // 기술마다 층을 여러 개 고를 수 있음 / 고른 층의 JOIN UP·NOC 는 기술 이름 옆에 바로
    //   (출입방법은 층마다 하나라서, 같은 층을 쓰는 다른 기술 칸에도 같이 바뀜)
    for (var ti = 0; ti < 4; ti++) {
      final k = '$key.$ti';
      final sel = m.val(k).split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      final floors = m.floorsAt(key, ti);
      final tg = GaetongModel.techs[ti];
      rf.rows.add(_row([
        SizedBox(
          width: 48,
          child: Text(tg, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _teal)),
        ),
        for (final f in floors) ...[
          if (floors.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(f, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _indigoDark)),
            ),
          for (final op in ['JOIN UP', 'NOC'])
            _chip(op, m.floorJoinOf(key, f) == op, () => m.setVal('$key.j.$f', op), rect: true, join: true),
        ],
        _br(),
        for (final op in GaetongModel.floorOpts) _chip(op, sel.contains(op), () => m.toggleFloor(key, ti, op)),
        if (sel.contains('기타')) _inp('$k.e', '예: B2', width: 80),
      ], done: sel.isNotEmpty, bg: const Color(0xFFFAFBFD)));
    }
    // [국사정보 수정] : 개통 완료를 기다리지 않고 바로 통합국 F열로 (엑셀에서는 바뀐 칸이 빨간 글씨)
    if (center.isNotEmpty && xl.isNotEmpty && xl != src && src.isNotEmpty && !widget.canEditCenter) {
      rf.rows.add(_row([_txt("이미 저장된 국사정보를 바꾸려면 개통 '수정' 권한이 필요해요 (관리자에게 요청)", 'warn')]));
    } else if (center.isNotEmpty && xl.isNotEmpty && xl != src) {
      rf.rows.add(_row([
        _chip(_savingCenter ? '보내는 중…' : (src.isNotEmpty ? '국사정보 수정' : '국사정보 저장'), false, _savingCenter
            ? null
            : () async {
                setState(() => _savingCenter = true);
                try {
                  await CenterService.saveFloor(center, xl);
                  m.setVals({'$key.src': xl, '$key.center': center});
                  if (mounted) _toast(context, '$center 국사정보를 통합국 F열로 보냈어요. 엑셀을 열면 바뀐 칸이 빨간 글씨로 보여요.');
                } catch (e) {
                  if (mounted) _toast(context, '보내기 실패: $e');
                } finally {
                  if (mounted) setState(() => _savingCenter = false);
                }
              }, primary: true),
        _txt(src.isNotEmpty ? '불러온 내용과 달라요' : '아직 통합국에 없는 국사정보', 'hint'),
      ]));
    }
    rf.note = xl.isNotEmpty ? '엑셀 통합국 F열 ▸ $xl' : 'JOIN UP·NOC는 밴드에는 안 올라가고 엑셀 통합국 F열에만 들어가요';
    rf.preview = m.floorLine(key);
  }

  // ---------------- 항목 하나 ----------------
  Widget _field(GItem it, String key) {
    final label = it.form ?? it.label;
    final labelW = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(label, style: const TextStyle(fontSize: 12, color: _sub)),
    );
    switch (it.type) {
      case 'text':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          labelW,
          _SyncInput(key: ValueKey('in:$key'), value: m.val(key), hint: it.ph ?? '', onChanged: (s) => m.setVal(key, s)),
        ]);
      case 'combo':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          labelW,
          _SyncInput(key: ValueKey('in:$key'), value: m.val(key), hint: it.ph ?? '', onChanged: (s) => m.setVal(key, s)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final op in it.opts) _chip(op, m.v(key) == op, () => m.setVal(key, m.v(key) == op ? '' : op)),
          ]),
        ]);
      case 'choice':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          labelW,
          Wrap(spacing: 6, runSpacing: 6, children: _chipsFor(key, it.opts)),
        ]);
      case 'memo':
      case 'memoRef':
        final rk = it.type == 'memoRef' ? '${m.keyOf(it.ref!)}.${it.sub}' : key;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          labelW,
          _SyncInput(key: ValueKey('in:$rk'), value: m.val(rk), hint: it.ph ?? '', multiline: true, onChanged: (s) => m.setVal(rk, s)),
        ]);
      case 'group':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var j = 0; j < it.subs.length; j++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 3, top: 4),
              child: Text(it.subForm.isNotEmpty ? it.subForm[j] : it.subs[j],
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _teal)),
            ),
            _SyncInput(
                key: ValueKey('in:$key.$j'),
                value: m.val('$key.$j'),
                hint: j == 0 ? (it.ph ?? '') : '',
                multiline: true,
                onChanged: (s) => m.setVal('$key.$j', s)),
          ],
        ]);
      case 'photo':
        final list = _photos[key] ?? [];
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE0E8)), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Row(children: [
              Icon(Icons.circle, size: 8, color: list.isNotEmpty ? const Color(0xFF2E7D32) : const Color(0xFFB0B4C0)),
              const SizedBox(width: 6),
              Expanded(child: Text(it.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              IconButton(tooltip: '카메라 촬영', icon: const Icon(Icons.photo_camera_outlined, color: _indigo), onPressed: () => _takePhotos(key, it.label)),
              IconButton(tooltip: '갤러리에서 선택', icon: const Icon(Icons.photo_library_outlined, color: _indigo), onPressed: () => _pickPhotos(key)),
            ]),
            if (list.isNotEmpty) _thumbs(key),
          ]),
        );
      default:
        final rf = _rows(it, key);
        if (rf.hidden) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!it.noLabel) labelW,
          for (final r in rf.rows) Padding(padding: const EdgeInsets.only(bottom: 6), child: r),
          if (rf.onAdd != null)
            TextButton.icon(
              onPressed: rf.onAdd,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(rf.addLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (rf.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(rf.note, style: const TextStyle(fontSize: 12, color: _sub))),
          if (rf.preview.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(color: const Color(0xFFF1F8E9), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('밴드 표시', style: TextStyle(fontSize: 11, color: Color(0xFF33691E))),
                Text(rf.preview, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1B5E20))),
              ]),
            ),
        ]);
    }
  }

  // ---------------- 칸(섹션) 하나 ----------------
  Widget _section(int si) {
    final sec = widget.tpl.sections[si];
    var filled = 0, total = 0;
    final fields = <Widget>[];
    for (final x in m.items.where((x) => x.si == si)) {
      if (x.it.hidden) continue;
      if (x.it.type != 'photo' && x.it.type != 'units' && !x.it.opt) {
        total++;
        if (m.filled(x.it, x.key)) filled++;
      }
      fields.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _field(x.it, x.key)));
    }
    final done = total > 0 && filled == total;
    final hasBtns = sec.photo;
    // 사진 칸(현장 사진이 있는 칸): 맨 위에 센싱
    if (widget.tpl.tech != 'DU' && m.items.any((x) => x.si == si && x.it.type == 'photo')) {
      fields.insert(0, Padding(padding: const EdgeInsets.only(bottom: 10), child: _sensingBox()));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: done ? _doneBg : Colors.white,
        border: Border.all(color: done ? _doneBorder : Colors.transparent),
        borderRadius: BorderRadius.circular(10),
        boxShadow: done ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            Container(width: 4, height: 20, decoration: BoxDecoration(color: _indigoDark, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Expanded(
                child: Text(sec.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _indigoDark))),
            if (total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: done ? const Color(0xFFE8F5E9) : const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(10)),
                child: Text('$filled/$total',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: done ? const Color(0xFF1B5E20) : _sub)),
              )
            else if (sec.note != null)
              Text(sec.note!, style: const TextStyle(fontSize: 12, color: _sub)),
          ]),
        ),
        // 센싱·카메라·갤러리 버튼은 제목 아래 오른쪽 빈자리에 (긴 제목이 잘리지 않게)
        Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 칸 사진: 제목 바로 아래 (카메라·갤러리 버튼과 같은 줄) → 넣자마자 그 자리에서 보임
            if (sec.photo && (_photos[_secKey(sec)] ?? const []).isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFDDE0E8)))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: 32,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${sec.title} 사진', style: const TextStyle(fontSize: 13, color: _teal, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  _thumbs(_secKey(sec)),
                ]),
              ),
            ...fields,
          ]),
          if (hasBtns)
            Positioned(
              top: 0,
              right: 0,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (sec.photo) _photoBtns(_secKey(sec), _secLabel(sec), compact: true),
              ]),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = m.names;
    final photoTotal = _allPhotos.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _onBack),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('개통 ${widget.tpl.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(names.isEmpty ? '' : names.first + (names.length > 1 ? ' 외 ${names.length - 1}' : ''),
                style: const TextStyle(fontSize: 12, color: Color(0xFFC5CAE9)), overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                _saveTimer?.cancel();
                await _saveDraft();
                if (context.mounted) _toast(context, '임시저장되었습니다. (입력할 때마다 자동 저장돼요)');
              },
              child: const Text('임시저장', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
            // 화면 밖 칸도 미리 만들어 둠 → [돌아가서 입력] 때 빠진 칸으로 바로 이동
            cacheExtent: 100000,
            children: [for (var si = 0; si < widget.tpl.sections.length; si++) _section(si)],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _goPreview,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A032), foregroundColor: Colors.white, shape: const StadiumBorder()),
                child: Text('밴드 본문 미리보기 (사진 $photoTotal장)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RF {
  final List<Widget> rows = [];
  String addLabel = '';
  VoidCallback? onAdd;
  String note = '';
  String preview = '';
  bool hidden = false;
}

/// 입력칸: 글자를 치는 동안에는 그대로 두고, 밖에서 값이 바뀌면(자동 채움 등) 화면에 반영
class _SyncInput extends StatefulWidget {
  final String value;
  final String hint;
  final bool numeric;
  final bool multiline;
  final bool center;
  final bool focusNow; // true 가 되는 순간 입력 커서를 넣음 (빠진 칸으로 이동)
  final ValueChanged<String> onChanged;

  const _SyncInput({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.numeric = false,
    this.multiline = false,
    this.center = false,
    this.focusNow = false,
  });

  @override
  State<_SyncInput> createState() => _SyncInputState();
}

class _SyncInputState extends State<_SyncInput> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(covariant _SyncInput old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
    if (widget.focusNow && !old.focusNow) {
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _f.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _f,
      onChanged: widget.onChanged,
      keyboardType: widget.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : (widget.multiline ? TextInputType.multiline : TextInputType.text),
      minLines: 1,
      maxLines: widget.multiline ? null : 1,
      textAlign: widget.center ? TextAlign.center : TextAlign.start,
      style: const TextStyle(fontSize: 15, color: _ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: const TextStyle(color: Color(0xFFA0A4B0)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF9AA0B4))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF9AA0B4))),
      ),
    );
  }
}
