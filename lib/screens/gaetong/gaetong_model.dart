// ============================================================
// 개통 양식 + 입력값 규칙 + 밴드 본문 만들기
// (Claude "개통 화면 미리보기" 확정본을 그대로 옮김, 2026-10-26)
//
//  - 항목/선택지/기본값을 바꾸려면 templates() 와 matUsages() 를 고치면 됩니다.
//  - 입력값은 모두 values[키] = 글자 로 저장 (임시저장도 이 Map 그대로)
// ============================================================

/// 양식의 항목 하나
class GItem {
  final String label;
  String type;
  List<String> opts;
  String? id, def, ph, form, after, before, ref;
  String? matsFrom, attFrom, trayFrom, rmatsFrom, shelfFrom, sunFrom;
  bool half, noLabel, opt, fold, lsh, remote, gap, cc, giro, inline, hidden, noBody;
  List<String> subs, subForm, msOpts;
  int sub;

  GItem(
    this.label, {
    this.type = 'text',
    this.opts = const [],
    this.id,
    this.def,
    this.ph,
    this.form,
    this.after,
    this.before,
    this.ref,
    this.matsFrom,
    this.attFrom,
    this.trayFrom,
    this.rmatsFrom,
    this.shelfFrom,
    this.sunFrom,
    this.half = false,
    this.noLabel = false,
    this.opt = false,
    this.fold = false,
    this.lsh = false,
    this.remote = false,
    this.gap = false,
    this.cc = false,
    this.giro = false,
    this.inline = false,
    this.hidden = false,
    this.noBody = false,
    this.subs = const [],
    this.subForm = const [],
    this.msOpts = const [],
    this.sub = 0,
  });
}

class GSection {
  String title;
  final String? note;
  List<GItem> items;
  bool photo; // 칸 제목 옆에 카메라·갤러리 버튼
  GSection(this.title, this.items, {this.note, this.photo = false});
}

class GTemplate {
  final String tech; // 5G / 4G
  final String eq; // AAU / PRU / GIRO / RRU / MIBOS
  final String unit; // AAU_1 처럼 쓰는 장비 이름
  final List<GSection> sections;
  GTemplate(this.tech, this.eq, this.sections, {String? unit}) : unit = unit ?? 'AAU';
  String get name => '$tech $eq';
}

/// 자재 사용처
class Usage {
  final String id, label;
  final String? grp; // MIBOS: L9TU / MHS 묶음
  final int? fl; // 국사정보 몇 번째 층을 붙일지 (0=3G 1=4G 2=5G 3=사업자)
  final bool qty, fixed, rdef;
  final Map<String, String>? def; // 기본 타입 (c 색 / a,ap 한쪽 / b,bp 반대쪽)
  const Usage(this.id, this.label,
      {this.grp, this.fl, this.qty = false, this.fixed = false, this.rdef = false, this.def});
}

class MatEntry {
  final String id, p, uid;
  MatEntry(this.id, this.p, this.uid);
}

class ItemKey {
  final GItem it;
  final String key;
  final int si;
  ItemKey(this.it, this.key, this.si);
}

/// 통합국 시트 한 줄 (E열 중심국명, F열 층/출입방법 정보)
class CenterInfo {
  final String name;
  final String floor;
  CenterInfo(this.name, this.floor);
}

// ------------------------------------------------------------
// 양식
// ------------------------------------------------------------
List<GTemplate> gaetongTemplates() {
  GItem combo(String l, List<String> o, {String? def, String? ph, String? after}) =>
      GItem(l, type: 'combo', opts: o, def: def, ph: ph, after: after);
  GItem choice(String l, List<String> o, {String? def, String? id, bool noBody = false}) =>
      GItem(l, type: 'choice', opts: o, def: def, id: id, noBody: noBody);
  GItem memo(String l, {String? id, bool opt = false}) => GItem(l, type: 'memo', id: id, opt: opt);

  const moda = ['S-MUX', 'C-MUX', 'L-MUX', 'OCM', 'PON'];

  GItem sauop() => combo('사업구분', ['신설', '이설', '증설'], def: '신설', ph: '선택 또는 입력');
  GItem gaetongYn() => choice('개통여부', ['개통', '미개통'], def: '개통');
  GItem mother() => GItem('모국명(중심국/RT)', type: 'mother', id: 'mother');
  GItem mux(String after) => GItem('MUX SHELF위치', type: 'mux', id: 'mux', after: after);
  // 광사업자: 기본 선택 없음, 화면은 신규광공유모듈 아래 / 밴드 본문은 엑셀 양식 자리(after)
  GItem optCarrier(String after) => combo('광사업자', ['SKT', 'SKB', 'KT', 'LG'], ph: '선택 또는 입력', after: after);
  GSection optBox({String after = 'mother'}) => GSection('광함체 · 공유모듈', [
        GItem('미사용광함체', type: 'chips', opts: ['KT', 'LG', 'SKB'], opt: true),
        GItem('기존광공유모듈', type: 'module', opts: moda, id: 'oldMod', fold: true, opt: true),
        GItem('신규광공유모듈', type: 'module', opts: moda, id: 'newMod'),
        optCarrier(after),
      ]);
  GItem waterproof() => choice('방수관', ['1EA', '2EA', '3EA', '4EA']);
  GItem sticker() => choice('무선국스티커부착여부', ['완료', '미완료']);
  GItem ringmux() => GItem('링먹스', opt: true);
  GItem note() => memo('특이사항', id: 'note', opt: true);
  GItem mhs() => GItem('L9TU · MHS', type: 'mhs', noLabel: true, giro: true);
  GItem centerMats({bool lsh = false}) => GItem('중심국 자재', type: 'mats', id: 'mats', noLabel: true, lsh: lsh);
  GItem remoteMats() => GItem('리모트 자재', type: 'mats', id: 'rmats', noLabel: true, remote: true);
  GItem att() => GItem('ATT', type: 'att', id: 'att', opt: true);
  GItem tray() => GItem('케이블정리대', type: 'tray', id: 'tray', noLabel: true);
  GSection mats({bool lsh = false}) => GSection('자재내역', [
        centerMats(lsh: lsh),
        att(),
        tray(),
        GItem('중심국 기타 자재 (직접 입력)', type: 'memoRef', ref: 'matgrp', sub: 0, opt: true, ph: '예: 브라켓×1EA'),
        remoteMats(),
        GItem('리모트 기타 자재 (직접 입력)', type: 'memoRef', ref: 'matgrp', sub: 1, opt: true),
        GItem('자재내역', type: 'group', id: 'matgrp', hidden: true, subs: ['중심국', '리모트'], gap: true,
            matsFrom: 'mats', attFrom: 'att', trayFrom: 'tray', rmatsFrom: 'rmats'),
      ]);
  // 선번: 화면에서는 자재내역 중심국/리모트 바로 아래로 나눠서 (아래 for 문에서 옮김)
  GSection sunbun() => GSection('선번', []);
  GSection photo() => GSection('사진', [GItem('현장 사진', type: 'photo')], note: '밴드 첨부용 (본문에는 안 들어감)');
  GSection basic() => GSection('기본정보', [sauop(), gaetongYn(), mother()]);

  // 5G AAU / PRU : 같은 양식, 장비 이름만 다름
  GTemplate fiveG(String unit) => GTemplate('5G', unit, [
        basic(),
        optBox(after: 'mux'),
        GSection('개통 $unit', [GItem('개통 장비', type: 'units', noLabel: true)]),
        GSection('MUX · SFP', [mux('mother'), GItem('SFP', type: 'sfpU')]),
        GSection('방수관 · 알람케이블', [waterproof(), GItem('알람케이블', type: 'alarmU')]),
        GSection('연동현황', [GItem('연동현황', type: 'link', noLabel: true)]),
        GSection('5G 케이블', [GItem('5G 케이블', type: 'cableU', noLabel: true)]),
        GSection('스티커 · 특이사항', [sticker(), note()]),
        mats(lsh: unit == 'PRU'),
        sunbun(),
        photo(),
      ], unit: unit);

  final giro = GTemplate('5G', 'GIRO', [
    basic(),
    optBox(),
    GSection('5G 장비', [GItem('개통 GIRO', type: 'units'), mux('note'), GItem('5G SFP', type: 'sfpU', cc: true)]),
    GSection('4G 장비', [
      mhs(),
      GItem('SFP(4G)', type: 'pick', form: '4G SFP', opts: ['1310/1550 1SET', '1430/1490 1SET', '1350 6G 1SET', '1350D/1350R 1SET'])
    ]),
    GSection('스티커 · 특이사항', [sticker(), ringmux(), note()]),
    mats(),
    sunbun(),
    photo(),
  ], unit: 'GIRO');

  final rru = GTemplate('4G', 'RRU', [
    basic(),
    optBox(),
    GSection('장비', [GItem('SFP', type: 'sfpMulti', opts: ['35L/H', '59L/H', '27/41', '850'])]),
    GSection('방수관 · 알람케이블', [waterproof(), GItem('알람케이블', type: 'alarm1')]),
    GSection('정류기 연동현황',
        [GItem('정류기 연동현황', type: 'link', inline: true, noLabel: true, msOpts: ['800', '1.8', '2.1', '2.6'])]),
    GSection('스티커 · 특이사항', [sticker(), ringmux(), note()]),
    mats(),
    sunbun(),
    photo(),
  ]);

  final mibos = GTemplate('4G', 'MIBOS', [
    basic(),
    optBox(),
    GSection('장비', [mhs()]),
    GSection('SFP', [GItem('SFP', type: 'sfpMulti', form: '4G SFP', opts: ['1310/1550', '1430/1490', '1350 6G', '1350D/1350R', '850'])]),
    GSection('특이사항 · 자재내역', [
      centerMats(),
      att(),
      tray(),
      remoteMats(),
      GItem('특이사항&자재내역', type: 'memo', id: 'matgrp', opt: true, form: '특이사항 & 기타 자재 (여러 줄)',
          ph: '예: (외장)SC/APC-FC/APC 5M×1EA(IJP ~ IRO)', matsFrom: 'mats', attFrom: 'att', trayFrom: 'tray', rmatsFrom: 'rmats'),
    ]),
    sunbun(),
    photo(),
  ]);

  final all = [fiveG('AAU'), fiveG('PRU'), giro, rru, mibos];
  for (final x in all) {
    // 4G: 케이블정리대 없음, 신규광공유모듈도 접어두고 선택 항목
    if (x.tech == '4G') {
      for (final s in x.sections) {
        s.items = s.items.where((y) => y.id != 'tray').toList();
        for (final y in s.items) {
          if (y.id == 'newMod') {
            y.fold = true;
            y.opt = true;
          }
        }
      }
    }
    // 5G: 신규광공유모듈 아래 MUX SHELF 사용유무 (사용이면 중심국 자재에 'MUX SHELF×1EA')
    if (x.tech == '5G') {
      for (final s in x.sections) {
        final ni = s.items.indexWhere((y) => y.id == 'newMod');
        if (ni >= 0) {
          s.items.insert(ni + 1, choice('MUX SHELF 사용유무', ['사용', '미사용'], def: '미사용', id: 'shelf', noBody: true));
        }
        for (final y in s.items) {
          if (y.id == 'matgrp') y.shelfFrom = 'shelf';
        }
      }
    }
    // 자재내역 칸을 중심국 / 리모트로 나눔
    final mi = x.sections.indexWhere((s) => s.items.any((y) => y.id == 'rmats'));
    if (mi >= 0) {
      final s = x.sections[mi];
      final ri = s.items.indexWhere((y) => y.id == 'rmats');
      final rest = s.items.sublist(ri);
      x.sections.replaceRange(mi, mi + 1, [
        GSection('자재내역 · 중심국', s.items.sublist(0, ri)),
        GSection(rest.any((y) => y.type == 'memo') ? '자재내역 · 리모트 · 특이사항' : '자재내역 · 리모트', rest),
      ]);
    }
    // 선번: 자재내역에서 고른 사용처마다 입력칸 + 사진 (밴드 본문은 자재내역 뒤에 한 번에)
    final sb = x.sections.indexWhere((s) => s.title == '선번');
    if (sb >= 0) {
      x.sections.removeAt(sb);
      final ci = x.sections.indexWhere((s) => s.title == '자재내역 · 중심국');
      x.sections.insert(ci + 1, GSection('선번 · 중심국', [GItem('선번 중심국', type: 'sunU', sunFrom: 'mats', noLabel: true, noBody: true)]));
      final ri = x.sections.indexWhere((s) => s.title.startsWith('자재내역 · 리모트'));
      x.sections.insert(ri + 1, GSection('선번 · 리모트', [
        GItem('선번 리모트', type: 'sunU', sunFrom: 'rmats', noLabel: true, noBody: true),
        GItem('선번', type: 'sunbun', hidden: true),
      ]));
    }
    // 사진 버튼이 붙는 칸
    for (final s in x.sections) {
      if (const ['광함체 · 공유모듈', 'MUX · SFP', '5G 장비', '스티커 · 특이사항', '자재내역 · 리모트 · 특이사항'].contains(s.title)) s.photo = true;
    }
    // 국사정보: 화면은 기본정보 바로 아래 / 밴드 본문은 자재내역 바로 앞
    x.sections.insert(1, GSection('국사정보', [GItem('국사정보', type: 'floors', id: 'floors', form: '중심국 층 선택', before: 'matgrp')]));
    // 입력 순서: 중심국 먼저, 리모트(현장)는 그다음 (밴드 본문 순서는 그대로)
    //  5G AAU·PRU: MUX·SFP 다음 / GIRO: 5G 장비·4G 장비 다음 / 4G: 국사정보 바로 다음
    final center = x.sections.where((s) => s.title == '자재내역 · 중심국' || s.title == '선번 · 중심국').toList();
    if (center.isNotEmpty) {
      x.sections.removeWhere(center.contains);
      final anchor = x.tech == '4G' ? '국사정보' : (x.eq == 'GIRO' ? '4G 장비' : 'MUX · SFP');
      final ai = x.sections.indexWhere((s) => s.title == anchor);
      x.sections.insertAll(ai + 1, center);
    }
  }
  return all;
}

// ------------------------------------------------------------
// 입력값 + 규칙
// ------------------------------------------------------------
class GaetongModel {
  final GTemplate tpl;
  String station;
  Map<String, String> values;
  List<CenterInfo> centers;
  final void Function() onChanged;

  late final List<ItemKey> items = () {
    final out = <ItemKey>[];
    var n = 0;
    for (var si = 0; si < tpl.sections.length; si++) {
      for (final it in tpl.sections[si].items) {
        out.add(ItemKey(it, 'k$n', si));
        n++;
      }
    }
    return out;
  }();

  GaetongModel(this.tpl, {required this.station, required this.values, required this.centers, required this.onChanged});

  String? keyOf(String id) {
    for (final x in items) {
      if (x.it.id == id) return x.key;
    }
    return null;
  }

  ItemKey? itemOf(String id) {
    for (final x in items) {
      if (x.it.id == id) return x;
    }
    return null;
  }

  /// 처음 시작할 때 기본값
  static Map<String, String> defaults(GTemplate tpl) {
    final m = GaetongModel(tpl, station: '', values: {}, centers: const [], onChanged: () {});
    final d = <String, String>{r'$units': '1'};
    for (final x in m.items) {
      if (x.it.def != null) d[x.key] = x.it.def!;
      if (x.it.type == 'mother') d['${x.key}.r'] = '직결';
      if (x.it.type == 'tray') d['${x.key}.q'] = '2';
      if (x.it.type == 'alarm1') d['${x.key}.q'] = '1';
    }
    return d;
  }

  String val(String k) => values[k] ?? '';
  String v(String k) => val(k).trim();

  void setVals(Map<String, String> o) {
    o.forEach((k, x) {
      if (x.isEmpty) {
        values.remove(k);
      } else {
        values[k] = x;
      }
    });
    onChanged();
  }

  void setVal(String k, String x) => setVals({k: x});

  List<String> get names => station.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  // ----- 개통 장비 번호 (AAU_1~4 공통) -----
  List<int> units() {
    final u = val(r'$units').split(',').where((x) => x.isNotEmpty).map(int.parse).toList()..sort();
    return u.isEmpty ? [1] : u;
  }

  void addUnit([int? n]) {
    final u = units();
    final next = n ?? [1, 2, 3, 4].firstWhere((x) => !u.contains(x), orElse: () => 0);
    if (next == 0) return;
    setVal(r'$units', ([...u, next]..sort()).join(','));
  }

  void removeUnit(int n) {
    final u = units().where((x) => x != n).toList();
    if (u.isEmpty) return;
    setVal(r'$units', u.join(','));
  }

  // ----- 광공유모듈 -----
  String modFmt(String key) {
    final b = v(key);
    if (b.isEmpty) return '';
    final sub = v('$key.sub');
    if (b == 'OCM') {
      if (sub.isEmpty) return 'OCM';
      if (sub == '기타') {
        final e = v('$key.etc');
        return e.isNotEmpty ? 'OCM-$e' : 'OCM';
      }
      return 'OCM-$sub';
    }
    if (b == 'PON') return 'PON$sub';
    return b;
  }

  String modKey(String key, int e) => e == 1 ? key : '$key#$e';
  int modCount(String key) => (int.tryParse(val('$key.n')) ?? 1).clamp(1, 2).toInt();
  String modAll(String key) {
    final out = <String>[];
    for (var e = 1; e <= modCount(key); e++) {
      final f = modFmt(modKey(key, e));
      if (f.isNotEmpty) out.add(f);
    }
    return out.join(', ');
  }

  String modBase() {
    final nk = keyOf('newMod'), ok = keyOf('oldMod');
    if (nk != null && v(nk).isNotEmpty) return v(nk);
    if (ok != null && v(ok).isNotEmpty) return v(ok);
    return '';
  }

  String pickFmt(String key) {
    final main = v(key) == '기타' ? v('$key.etc') : v(key);
    return [main, v('$key.set')].where((x) => x.isNotEmpty).join(' ');
  }

  String alarm1Fmt(String key) {
    if (v('$key.o').isNotEmpty) return v('$key.etc');
    final l = v('$key.len');
    return l.isNotEmpty ? '${l}M×${v('$key.q').isEmpty ? '1' : v('$key.q')}EA' : '';
  }

  String autoSpec() {
    final b = modBase();
    if (b == 'S-MUX' || b == 'PON') return '5G 2C SC/APC-LC/PC';
    if (b == 'L-MUX' || b == 'C-MUX') return '5G 2C LC/PC-LC/PC';
    return '';
  }

  String motherFmt(String key) {
    final c = v('$key.c'), r = v('$key.r');
    return c.isNotEmpty && r.isNotEmpty ? '$c/$r' : (c.isNotEmpty ? c : r);
  }

  String muxFmt(String key) {
    String g(String s) => v('$key.$s');
    if ([g('a'), g('b'), g('c'), g('d'), g('e')].every((x) => x.isEmpty)) return '';
    final pre = (g('a').isNotEmpty || g('b').isNotEmpty) ? 'R${g('a')}-${g('b')}_' : '';
    return '${pre}S-MUX#${g('c')}_Shelf${g('d')}-${g('e')}${g('bk').isNotEmpty ? '(배면)' : ''}';
  }

  String sfpVal(String key, int n) {
    final sp = v('$key.$n.sp'), no = v('$key.$n.no');
    final cc = n > 1 && v('$key.$n.cc').isNotEmpty;
    if (sp.isEmpty && no.isEmpty && !cc) return '';
    return [cc ? 'CC' : modBase(), sp, no.isNotEmpty ? '$no번' : ''].where((x) => x.isNotEmpty).join(' ');
  }

  String alarmVal(String key, int n) {
    if (v('$key.$n.fac').isNotEmpty) return '시설팀 포설';
    final l = v('$key.$n.len');
    return l.isNotEmpty ? '${l}M×1EA' : '';
  }

  String alarmSum(String key) {
    final tally = <String, int>{};
    var fac = false;
    for (final n in units()) {
      if (v('$key.$n.fac').isNotEmpty) {
        fac = true;
        continue;
      }
      final l = v('$key.$n.len');
      if (l.isEmpty) continue;
      tally[l] = (tally[l] ?? 0) + 1;
    }
    return [...tally.entries.map((e) => '${e.key}M×${e.value}EA'), if (fac) '시설팀 포설'].join(', ');
  }

  String cableVal(String key, int n) {
    final p = '$key.$n.';
    final len = v('${p}len'), real = v('${p}real'), fac = v('${p}fac');
    if (fac.isNotEmpty) return '시설팀 포설';
    if (len.isEmpty && real.isEmpty) return '';
    final spec = v('${p}spec').isNotEmpty ? v('${p}spec') : autoSpec();
    return [spec, len.isNotEmpty ? '${len}M' : '', real.isNotEmpty ? '(${real}M)' : ''].where((x) => x.isNotEmpty).join(' ');
  }

  // ----- 국사정보 (층 / JOIN UP·NOC) -----
  static const techs = ['3G', '4G', '5G', '사업자'];

  String floorAt(String key, int ti) {
    var f = v('$key.$ti');
    if (f == '기타') {
      f = v('$key.$ti.e');
      if (f.isNotEmpty && !f.endsWith('층')) f += '층';
    }
    return f;
  }

  String floorJoin(String key, int ti) {
    final own = v('$key.$ti.t');
    if (own.isNotEmpty) return own;
    final f = floorAt(key, ti), f5 = floorAt(key, 2);
    return (ti == 2 || (f.isNotEmpty && f == f5)) ? 'NOC' : 'JOIN UP';
  }

  /// 밴드: '3G : 1층 / 4G : 2층 / 5G,사업자 : 3층'
  String floorLine(String key) {
    final map = <String, List<String>>{};
    for (var ti = 0; ti < 4; ti++) {
      final f = floorAt(key, ti);
      if (f.isEmpty) continue;
      (map[f] ??= []).add(techs[ti]);
    }
    return map.entries.map((e) => '${e.value.join(',')} : ${e.key}').join(' / ');
  }

  /// 엑셀 통합국 F열: '3G : 4층(JOIN UP) / 5G,사업자 : 3층(NOC)'
  String floorExcelLine(String key) {
    final map = <String, List<String>>{};
    for (var ti = 0; ti < 4; ti++) {
      final f = floorAt(key, ti);
      if (f.isEmpty) continue;
      (map['$f(${floorJoin(key, ti)})'] ??= []).add(techs[ti]);
    }
    return map.entries.map((e) => '${e.value.join(',')} : ${e.key}').join(' / ');
  }

  static Map<int, List<String>> parseFloorLine(String line) {
    final out = <int, List<String>>{};
    for (final part in line.split('/')) {
      final m = RegExp(r'^(.+?)\s*:\s*(.+?)\s*\((JOIN UP|NOC)\)\s*$').firstMatch(part.trim());
      if (m == null) continue;
      for (final tg in m.group(1)!.split(',')) {
        final ti = techs.indexOf(tg.trim());
        if (ti >= 0) out[ti] = [m.group(2)!.trim(), m.group(3)!];
      }
    }
    return out;
  }

  /// 중심국명 입력/선택 → 통합국에 국사정보가 있으면 층·출입방법 자동 채움
  void applyCenter(String name) {
    final mk = keyOf('mother')!, fk = keyOf('floors');
    final o = <String, String>{'$mk.c': name};
    CenterInfo? hit;
    for (final c in centers) {
      if (c.name == name.trim()) hit = c;
    }
    if (fk != null && hit != null && hit.floor.isNotEmpty) {
      final p = parseFloorLine(hit.floor);
      const opts = ['1층', '2층', '3층', '4층', '5층', 'B1층'];
      for (var ti = 0; ti < 4; ti++) {
        final k = '$fk.$ti';
        o[k] = '';
        o['$k.e'] = '';
        o['$k.t'] = '';
        final x = p[ti];
        if (x == null) continue;
        if (opts.contains(x[0])) {
          o[k] = x[0];
        } else {
          o[k] = '기타';
          o['$k.e'] = x[0].replaceAll(RegExp(r'층$'), '');
        }
        o['$k.t'] = x[1];
      }
      o['$fk.src'] = hit.floor;
      o['$fk.center'] = hit.name;
    } else if (fk != null && v('$fk.src').isNotEmpty) {
      // 다른 중심국으로 바꾸면 자동으로 불러왔던 층 정보는 지움
      for (var ti = 0; ti < 4; ti++) {
        o['$fk.$ti'] = '';
        o['$fk.$ti.e'] = '';
        o['$fk.$ti.t'] = '';
      }
      o['$fk.src'] = '';
      o['$fk.center'] = '';
    }
    setVals(o);
  }

  String floorOf(int ti) {
    final fk = keyOf('floors');
    return fk == null ? '' : floorAt(fk, ti);
  }

  /// 개통 완료 때 통합국으로 보낼 국사정보 (새로 입력했거나 바뀐 경우만) — [중심국명, F열 문구]
  List<String>? centerToSave() {
    final mk = keyOf('mother'), fk = keyOf('floors');
    if (mk == null || fk == null) return null;
    final center = v('$mk.c');
    final xl = floorExcelLine(fk);
    if (center.isEmpty || xl.isEmpty || v('$fk.src') == xl) return null;
    return [center, xl];
  }

  // ----- ATT -----
  ({String name, bool multi, List<String> opts})? attKind() {
    final b = modBase();
    if (tpl.tech == '4G' && !b.contains('MUX')) return null; // 4G는 MUX를 골랐을 때만
    if (b == 'S-MUX' || b == 'PON') return (name: '개별ATT', multi: true, opts: ['0', '1', '3', '5', '7', '10', '15']);
    if (b == 'C-MUX' || b == 'L-MUX') return (name: '통합ATT', multi: false, opts: ['0', '1', '3', '5', '7', '10']);
    return null;
  }

  int attCount(String key) {
    final k = attKind();
    return (k != null && k.multi) ? (int.tryParse(val('$key.n')) ?? 1).clamp(1, 8).toInt() : 1;
  }

  /// '개별ATT 0dB×2EA, 3dB×2EA' (같은 dB는 수량 합침)
  List<String> attLines(String key) {
    final k = attKind();
    if (k == null) return [];
    final sum = <String, int>{};
    for (var e = 1; e <= attCount(key); e++) {
      final x = v('$key.$e.v');
      if (x.isEmpty || !k.opts.contains(x)) continue;
      sum[x] = (sum[x] ?? 0) + (int.tryParse(v('$key.$e.q')) ?? 1);
    }
    return sum.isEmpty ? [] : ['${k.name} ${sum.entries.map((e) => '${e.key}dB×${e.value}EA').join(', ')}'];
  }

  // ----- 자재 -----
  Map<String, String> remoteDef() {
    final b = modBase();
    final sc = b == 'S-MUX' || b == 'PON';
    return {'c': '외', 'a': 'SC', 'ap': '', 'b': sc ? 'SC' : 'LC', 'bp': sc ? '' : 'APC'};
  }

  String colorFmt(String c) => c == '적외' ? '(적)(외)' : (c.isNotEmpty ? '($c)' : '');
  String matEnd(String x, String pp) =>
      x == 'SC' ? 'SC/APC' : x == 'FC' ? 'FC/APC' : x == 'LC' ? (pp.isNotEmpty ? 'LC/$pp' : 'LC') : '';
  String matType(String p) {
    final a = matEnd(v('${p}a'), v('${p}ap')), b = matEnd(v('${p}b'), v('${p}bp'));
    return a.isNotEmpty && b.isNotEmpty ? '$a-$b' : (a.isNotEmpty ? a : b);
  }

  String matHead(String p, Usage? u, {bool ignoreRdef = false}) {
    if (u != null && u.fixed) return '(파) 2C LC/PC-LC/PC';
    final d = (u != null && u.rdef && !ignoreRdef && v('${p}custom').isEmpty)
        ? remoteDef()
        : {'c': v('${p}c'), 'a': v('${p}a'), 'ap': v('${p}ap'), 'b': v('${p}b'), 'bp': v('${p}bp')};
    final a = matEnd(d['a']!, d['ap']!), b = matEnd(d['b']!, d['bp']!);
    return [colorFmt(d['c']!), a.isNotEmpty && b.isNotEmpty ? '$a-$b' : (a.isNotEmpty ? a : b)].where((x) => x.isNotEmpty).join(' ');
  }

  List<Usage> matUsages(GItem it) {
    Map<String, String> d(String c, String a, String ap, String b, String bp) => {'c': c, 'a': a, 'ap': ap, 'b': b, 'bp': bp};
    const etc = Usage('etc', '기타 (직접 입력)');
    if (it.remote) {
      if (tpl.tech == '4G') {
        final rr = tpl.eq == 'RRU'
            ? [
                const Usage('ijp', 'IJP ~ RRU', rdef: true),
                Usage('rru2mux', 'RRU ~ MUX', def: d('외', 'LC', 'PC', 'LC', 'APC')),
                Usage('rru2ocm', 'RRU ~ OCM', def: d('외', 'FC', '', 'LC', 'PC')),
                Usage('ocm2ijp', 'OCM ~ IJP', def: d('외', 'SC', '', 'FC', '')),
              ]
            : [
                Usage('ro2ijp', 'RO ~ IJP', def: d('외', 'SC', '', 'FC', '')),
                Usage('ro2ocm', 'RO ~ OCM', def: d('외', 'FC', '', 'FC', '')),
                Usage('ro2mux', 'RO ~ MUX', def: d('외', 'FC', '', 'LC', 'APC')),
                Usage('ocm2ijp', 'OCM ~ IJP', def: d('외', 'SC', '', 'FC', '')),
              ];
        return [...rr, const Usage('etc', '기타 (직접 입력)', rdef: true)];
      }
      final m = modBase().isNotEmpty ? modBase() : 'MUX';
      return [Usage('ijp', 'IJP ~ $m', rdef: true), const Usage('etc', '기타 (직접 입력)', rdef: true)];
    }
    if (tpl.tech == '4G') {
      // 4G: 기본 색 (노), DU 층 = 4G층, L9TU·MHS 층 = 3G층
      Map<String, String> y(String b, [String bp = '']) => d('노', 'SC', '', b, bp);
      final l4 = tpl.eq == 'MIBOS'
          ? [
              Usage('du2l9', 'DU ~ L9TU', grp: 'L9TU', fl: 1, qty: true, def: y('LC', 'PC')),
              Usage('du2fdf', 'DU ~ 층간FDF', grp: 'L9TU', fl: 1, qty: true, def: y('LC', 'PC')),
              Usage('fdf2l9', '층간FDF ~ L9TU', grp: 'L9TU', fl: 0, qty: true, def: y('LC', 'PC')),
              Usage('mhs2ofd', 'MHS ~ 사업자OFD', grp: 'MHS', fl: 0, def: y('FC')),
              Usage('mhs2fdf', 'MHS ~ 층간FDF', grp: 'MHS', fl: 0, def: y('FC')),
              Usage('fdf2ofd', '층간FDF ~ 사업자OFD', grp: 'MHS', fl: 3, def: y('SC')),
            ]
          : [
              Usage('du2ofd', 'DU ~ 사업자OFD', fl: 1, def: y('LC', 'PC')),
              Usage('du2fdf', 'DU ~ 층간FDF', fl: 1, def: y('LC', 'PC')),
              Usage('fdf2ofd', '층간FDF ~ 사업자OFD', fl: 3, def: y('SC')),
            ];
      return [...l4, etc];
    }
    return [
      Usage('mux2ofd', 'MUX ~ 사업자OFD', fl: 2, def: d('파', 'SC', '', 'LC', 'APC')),
      Usage('mux2fdf', 'MUX ~ 층간FDF', fl: 2, def: d('파', 'SC', '', 'LC', 'APC')),
      Usage('fdf2ofd', '층간FDF ~ 사업자OFD', fl: 3, def: d('파', 'SC', '', 'SC', '')),
      const Usage('ls', 'LS판넬 ~ DS판넬', fixed: true),
      if (it.lsh) const Usage('lsh', 'L-MUX ~ LSH', fl: 2, fixed: true),
      etc,
    ];
  }

  Usage? usageOf(GItem it, String id) {
    for (final u in matUsages(it)) {
      if (u.id == id) return u;
    }
    return null;
  }

  List<String> matSel(String key) => val('$key.sel').split(',').where((x) => x.isNotEmpty).toList();

  List<MatEntry> matEntries(GItem it, String key) {
    final order = matUsages(it).map((x) => x.id).toList();
    int rank(String id) => id.startsWith('etc') ? 100 + (int.tryParse(id.substring(3)) ?? 0) : order.indexOf(id);
    final ids = matSel(key).where((id) => id.startsWith('etc') || order.contains(id)).toList()
      ..sort((a, b) => rank(a) - rank(b));
    return ids.map((id) => MatEntry(id, '$key.$id.', id.startsWith('etc') ? 'etc' : id)).toList();
  }

  void matToggle(GItem it, String key, String id, bool on) {
    var sel = matSel(key).where((x) => x != id).toList();
    final o = <String, String>{};
    if (on) {
      sel.add(id);
      if (id == 'lsh') sel = sel.where((x) => x != 'ls').toList();
      final u = usageOf(it, id);
      final p = '$key.$id.';
      if (u?.def != null && v('${p}c').isEmpty) u!.def!.forEach((s, x) => o['$p$s'] = x);
      // 자재 수량 기본 1 (중심국·리모트 공통)
      if (v('${p}q').isEmpty) o['${p}q'] = '1';
    } else if (id.startsWith('etc')) {
      for (final s in ['ut', 'edit', 'custom', 'c', 'a', 'ap', 'b', 'bp', 'len', 'q', 'r']) {
        o['$key.$id.$s'] = '';
      }
    }
    o['$key.sel'] = sel.join(',');
    setVals(o);
  }

  /// 사용처 문구 (밴드 표기는 붙여서: MUX~층간FDF_3층)
  String matUsage(GItem it, String p, String uid) {
    final ov = v('${p}ut');
    if (ov.isNotEmpty) return ov;
    final u = usageOf(it, uid);
    if (u == null || u.id == 'etc') return '';
    final f = u.fl != null ? floorOf(u.fl!) : '';
    return u.label.replaceAll(RegExp(r'\s*~\s*'), '~') + (f.isNotEmpty ? '_$f' : '');
  }

  String matLine(GItem it, MatEntry en) {
    final p = en.p;
    final u = usageOf(it, en.uid);
    final head = u != null ? matHead(p, u) : '';
    final len = v('${p}len'), q = v('${p}q'), r = v('${p}r'), use = matUsage(it, p, en.uid);
    if (len.isEmpty && use.isEmpty) return '';
    return [
      head,
      len.isNotEmpty ? '${len}M×${q.isEmpty ? '1' : q}EA' : (q.isNotEmpty ? '${q}EA' : ''),
      r.isNotEmpty ? '(${r}M)' : '',
      use.isNotEmpty ? '[$use]' : '',
    ].where((x) => x.isNotEmpty).join(' ');
  }

  /// 자재 하나 완료: 타입·길이·실거리·사용처 문구가 다 있어야 (수량은 기본 1)
  bool matEntryDone(GItem it, MatEntry en) {
    final u = usageOf(it, en.uid);
    if (u == null) return false;
    return matHead(en.p, u).isNotEmpty && v('${en.p}len').isNotEmpty && v('${en.p}r').isNotEmpty && matUsage(it, en.p, en.uid).isNotEmpty;
  }

  bool matDone(GItem it, String key) {
    final e = matEntries(it, key);
    return e.isNotEmpty && e.every((x) => matEntryDone(it, x));
  }

  List<String> matLines(GItem it, String key) =>
      matEntries(it, key).map((en) => matLine(it, en)).where((x) => x.isNotEmpty).toList();

  // ----- 선번 (자재내역에서 고른 사용처마다) -----
  /// 사용처 이름 (사진 위 글자, 밴드 본문): 예) MUX~사업자OFD_3층
  String sunLabel(GItem matIt, MatEntry en) {
    final t = matUsage(matIt, en.p, en.uid);
    if (t.isNotEmpty) return t;
    final u = usageOf(matIt, en.uid);
    if (u == null || u.id == 'etc') return '기타';
    return u.label.replaceAll(RegExp(r'\s*~\s*'), '~');
  }

  /// (자재 항목, 그 키, 사용처 목록)
  ({GItem it, String key, List<MatEntry> entries})? sunSource(GItem sunIt) {
    final mx = itemOf(sunIt.sunFrom ?? '');
    if (mx == null) return null;
    // LS판넬~DS판넬은 선번 필요 없음
    return (it: mx.it, key: mx.key, entries: matEntries(mx.it, mx.key).where((en) => en.uid != 'ls').toList());
  }

  List<String> sunLines(GItem sunIt, String key) {
    final src = sunSource(sunIt);
    if (src == null) return [];
    final l = <String>[];
    for (final en in src.entries) {
      final x = v('$key.${en.id}');
      if (x.isNotEmpty) l.add('${sunLabel(src.it, en)} : $x');
    }
    return l;
  }

  bool sunDone(GItem sunIt, String key) {
    final src = sunSource(sunIt);
    return src != null && src.entries.isNotEmpty && src.entries.every((en) => v('$key.${en.id}').isNotEmpty);
  }

  // ----- SFP 여러 개 (4G) -----
  List<String> sfpMultiSel(String key) => val('$key.sel').split(',').where((x) => x.isNotEmpty).toList();
  String sfpMultiFmt(GItem it, String key) {
    final sel = sfpMultiSel(key);
    final ids = [for (var i = 0; i < it.opts.length; i++) '$i', 'e'];
    return ids.where(sel.contains).map((id) {
      final name = id == 'e' ? v('$key.etc') : it.opts[int.parse(id)];
      final q = v('$key.$id.q');
      return name.isNotEmpty ? '$name×${q.isEmpty ? '1' : q}SET' : '';
    }).where((x) => x.isNotEmpty).join(', ');
  }

  // ----- 연동현황 -----
  int linkCount(String key) => (int.tryParse(val('$key.n')) ?? 1).clamp(1, 4).toInt();
  String linkLine(String key, int i) {
    final p = '$key.$i.';
    final mk = v('${p}mk');
    final m = v('${p}m') == '기타' ? v('${p}me') : v('${p}m');
    final s = v('${p}s') == '기타' ? v('${p}se') : v('${p}s');
    final bt = v('${p}bt');
    return [mk, m.isNotEmpty ? 'M$m' : '', s.isNotEmpty ? 'S$s' : '', bt.isNotEmpty ? '배터리 $bt' : ''].where((x) => x.isNotEmpty).join(' ');
  }

  List<String> linkLines(String key) =>
      [for (var i = 1; i <= linkCount(key); i++) linkLine(key, i)].where((x) => x.isNotEmpty).toList();

  // ----- 다른 항목 줄을 자재내역 본문에 끼워 넣기 -----
  List<String> linesFrom(String? id) {
    if (id == null) return [];
    final mx = itemOf(id);
    if (mx == null) return [];
    if (mx.it.type == 'mats') return matLines(mx.it, mx.key);
    if (mx.it.id == 'shelf') return v(mx.key) == '사용' ? ['MUX SHELF×1EA'] : [];
    if (mx.it.type == 'att') return attLines(mx.key);
    if (mx.it.type == 'tray') {
      final q = v('${mx.key}.q');
      return q.isNotEmpty ? ['케이블정리대×${q}EA'] : [];
    }
    return [];
  }

  // ------------------------------------------------------------
  // 밴드 본문
  // ------------------------------------------------------------
  /// 밴드 본문: 입력이 없는 항목은 줄 자체를 뺌
  List<String> out(GItem it, String key) {
    final u = tpl.unit;
    final us = units();
    if (it.noBody) return [];
    List<String> kv(String label, String x) => x.trim().isEmpty ? [] : ['$label : $x'];
    // 제목 줄 + 내용 줄 (내용이 없으면 제목도 뺌)
    List<String> head(String label, List<String> body) => body.isEmpty ? [] : ['$label :', ...body];
    switch (it.type) {
      case 'photo':
      case 'units':
      case 'mats':
      case 'att':
      case 'tray':
      case 'memoRef':
      case 'sunU':
        return [];
      case 'sunbun': {
        // 자재내역(리모트) 다음 한 줄 띄우고 선번
        final l = <String>[];
        for (final x in items.where((y) => y.it.type == 'sunU')) {
          final s = sunLines(x.it, x.key);
          if (s.isNotEmpty) l.addAll([x.it.sunFrom == 'rmats' ? '리모트' : '중심국', ...s]);
        }
        return l.isEmpty ? [] : ['', '${it.label} :', ...l];
      }
      case 'floors':
        return kv(it.label, floorLine(key));
      case 'memo': {
        final x = val(key).trimRight();
        return head(it.label, [
          for (final f in [it.matsFrom, it.attFrom, it.trayFrom, it.rmatsFrom]) ...linesFrom(f),
          if (x.trim().isNotEmpty) x,
        ]);
      }
      case 'group': {
        final parts = <List<String>>[];
        for (var j = 0; j < it.subs.length; j++) {
          final b = <String>[];
          final froms = j == 0 ? [it.matsFrom, it.shelfFrom, it.attFrom, it.trayFrom] : [it.rmatsFrom];
          for (final f in froms) {
            b.addAll(linesFrom(f));
          }
          final x = val('$key.$j').trimRight();
          if (x.trim().isNotEmpty) b.add(x);
          if (b.isNotEmpty) parts.add([it.subs[j], ...b]);
        }
        final l = <String>[];
        for (var j = 0; j < parts.length; j++) {
          if (j > 0 && it.gap) l.add('');
          l.addAll(parts[j]);
        }
        return head(it.label, l);
      }
      case 'module':
        return kv(it.label, modAll(key));
      case 'pick':
        return kv(it.label, pickFmt(key));
      case 'sfpMulti':
        return kv(it.label, sfpMultiFmt(it, key));
      case 'alarm1':
        return kv(it.label, alarm1Fmt(key));
      case 'mother':
        return kv(it.label, motherFmt(key));
      case 'mux':
        return kv(it.label, muxFmt(key));
      case 'chips':
        return kv(it.label, v(key));
      case 'sfpU':
        return [for (final n in us) ...kv('SFP ${u}_$n', sfpVal(key, n))];
      case 'alarmU':
        return [...kv('알람케이블', alarmSum(key)), for (final n in us) ...kv('${u}_$n', alarmVal(key, n))];
      case 'cableU':
        return head('5G 케이블', [for (final n in us) ...kv('${u}_$n', cableVal(key, n))]);
      case 'link':
        return it.inline ? kv(it.label, linkLines(key).join(' / ')) : head(it.label, linkLines(key));
      case 'mhs': {
        final l9 = v('$key.l9') == '기타' ? v('$key.l9e') : v('$key.l9');
        final m = v('$key.mhs');
        return [
          ...kv('L9TU', l9),
          ...kv('MHS', m.isEmpty ? '' : m == 'BR' ? 'BR수용' : m == 'SMHS' ? 'SMHS CU×1EA, PSU UNIT×1EA' : '$m×1EA'),
        ];
      }
      default:
        return kv(it.label, v(key));
    }
  }

  String buildBody() {
    final l = <String>['[개통] ${tpl.name}', '국소명 : ${names.join('\n')}'];
    // 화면 순서와 밴드 본문 순서가 다른 항목: before(그 항목 앞) / after(그 항목 뒤)
    void emit(ItemKey x) {
      if (x.it.id != null) {
        for (final y in items.where((y) => y.it.before == x.it.id)) {
          emit(y);
        }
      }
      l.addAll(out(x.it, x.key));
      if (x.it.id != null) {
        for (final y in items.where((y) => y.it.after == x.it.id)) {
          emit(y);
        }
      }
    }

    for (final x in items) {
      if (x.it.after == null && x.it.before == null) emit(x);
    }
    return l.join('\n');
  }

  // ------------------------------------------------------------
  // 입력 완료 (칸이 회색이 되는 기준)
  // ------------------------------------------------------------
  bool filled(GItem it, String key) {
    final us = units();
    switch (it.type) {
      case 'group':
        return [for (var j = 0; j < it.subs.length; j++) v('$key.$j')].any((x) => x.isNotEmpty);
      case 'module':
        return modAll(key).isNotEmpty;
      case 'floors':
        return floorLine(key).isNotEmpty;
      case 'mats':
        return matDone(it, key);
      case 'sunU':
        return sunDone(it, key);
      case 'sfpMulti':
        return sfpMultiFmt(it, key).isNotEmpty;
      case 'att':
        return attLines(key).isNotEmpty;
      case 'tray':
        return v('$key.q').isNotEmpty;
      case 'memoRef': {
        final rk = keyOf(it.ref!);
        return rk != null && v('$rk.${it.sub}').isNotEmpty;
      }
      case 'pick':
        return pickFmt(key).isNotEmpty;
      case 'alarm1':
        return alarm1Fmt(key).isNotEmpty;
      case 'mother':
        return v('$key.c').isNotEmpty;
      case 'mux':
        return muxFmt(key).isNotEmpty;
      case 'sfpU':
        return us.every((n) => sfpVal(key, n).isNotEmpty);
      case 'alarmU':
        return us.every((n) => alarmVal(key, n).isNotEmpty);
      case 'cableU':
        return us.every((n) => cableVal(key, n).isNotEmpty);
      case 'link':
        return linkLines(key).isNotEmpty;
      case 'mhs':
        return v('$key.mhs').isNotEmpty;
      default:
        return v(key).isNotEmpty;
    }
  }
}
