// ============================================================
// 실사 양식 정의 (엑셀 "실사 분류표" + 미리보기 확정본 기준)
// 항목을 추가/수정하려면 이 파일만 고치면 됩니다.
//  - 4G : 상면/입전 같은 항목 (상면은 앞에 RACK 추가)
//  - 5G : 상면/입전 같은 항목 (상면은 앞에 RACK 추가)
//  - 확인필요사항만 상면/입전이 조금 다름
// ============================================================

/// 입력칸 종류
enum FieldType {
  text, // 글자 입력
  number, // 숫자 키패드 입력
  choice, // 버튼 중 하나 선택
  cascade, // 1차 선택 → 2차 선택 (예: 납 축전지 → 1000)
  memo, // 여러 줄 입력
  fuse, // FA/FB 선택 + 숫자 → FA3
}

class FieldDef {
  final String label;
  final FieldType type;
  final List<String> options; // choice / fuse 용
  final Map<String, List<String>> cascade; // cascade 용
  final String suffix; // 뒤에 붙는 단위 (예: A, ' EA', m, 조)
  final String prefix; // 앞에 붙는 글자 (예: R → R3-3)
  final int? showIfIndex; // 같은 줄의 이 번호 칸이
  final String? showIfValue; // 이 값일 때만 보임

  const FieldDef(
    this.label, {
    this.type = FieldType.text,
    this.options = const [],
    this.cascade = const {},
    this.suffix = '',
    this.prefix = '',
    this.showIfIndex,
    this.showIfValue,
  });
}

/// 한 줄 = (필요사진 1개) + (필요항목 입력칸 0~N개)
class RowDef {
  final String? photo; // null 이면 사진 없음
  final List<FieldDef> fields;
  const RowDef({this.photo, this.fields = const []});
}

/// 섹션 (RACK, 정류기, 축전지, 냉방기 ...)
class SectionDef {
  final String id;
  final String title;
  final bool repeatable; // 정류기1, 정류기2 ... 처럼 추가 가능
  final int max;
  final String? note; // 안내 문구
  final List<RowDef> rows;
  final List<SectionDef> children; // 정류기 안의 축전지 처럼 하위 섹션

  const SectionDef({
    required this.id,
    required this.title,
    this.repeatable = false,
    this.max = 1,
    this.note,
    this.rows = const [],
    this.children = const [],
  });
}

/// 확인필요사항 한 줄 (기본 [불필요], [필요] 선택 시 fields 입력칸 표시)
class CheckDef {
  final String label;
  final List<FieldDef> fields;
  const CheckDef(this.label, this.fields);
}

class SurveyTemplate {
  final String id;
  final String place; // 상면 / 입전
  final String tech; // 4G / 5G
  final String rack; // 신규랙(증설) / 기존랙
  final List<SectionDef> sections;
  final List<CheckDef> checks;

  const SurveyTemplate({
    required this.id,
    required this.place,
    required this.tech,
    required this.rack,
    required this.sections,
    required this.checks,
  });

  /// 예: 상면 실사 · 4G · 신규랙(증설)
  String get name => '$place 실사 · $tech · $rack';

  /// 분류 선택 화면의 안내 문구 (하위 항목 포함)
  String get summary {
    final out = <String>[];
    void walk(List<SectionDef> list) {
      for (final s in list) {
        if (!out.contains(s.title)) out.add(s.title);
        walk(s.children);
      }
    }

    walk(sections);
    return out.join(' · ');
  }
}

// ------------------------------------------------------------
// 공통 선택지 / 입력칸
// ------------------------------------------------------------
const _models4G = ['CRS-1800', 'FAR-1800', 'CRS-2400', 'MBRS-1200'];
const _models5G = ['MR-H', 'MR1'];
const _leadFirst = {
  '납 축전지': ['800', '1000', '1200', '1600'],
  '리튬': ['1600', '2000', '2400'],
};
const _lithiumFirst = {
  '리튬': ['1600', '2000', '2400'],
  '납 축전지': ['800', '1000', '1200', '1600'],
};
const _coolerRT = ['5RT', '7.5RT', '10RT', '15RT'];
const _halonKg = ['50Kg', '100Kg'];
const _reuseOrAdd = ['기존활용', '증설필요'];

const _len = FieldDef('길이', type: FieldType.number, suffix: 'm');
const _qty = FieldDef('수량', type: FieldType.number, suffix: ' EA');
const _type = FieldDef('타입');
const _load = FieldDef('부하량', type: FieldType.number, suffix: 'A');
const _modules = FieldDef('모듈수량', type: FieldType.number, suffix: ' EA');
const _breaker = FieldDef('차단기용량', type: FieldType.number, suffix: 'A');
const _batteryQty = FieldDef('축전지 수량', type: FieldType.number, suffix: '조');

// ------------------------------------------------------------
// 공통 섹션
// ------------------------------------------------------------
const _rack = SectionDef(
  id: 'rack',
  title: 'RACK',
  rows: [
    RowDef(photo: '랙증설위치', fields: [FieldDef('랙번호', prefix: 'R')]),
    RowDef(photo: '랙증설위치 전면'),
    RowDef(photo: '랙증설위치 후면'),
    RowDef(photo: '냉방기 바라본사진(앞,뒤)'),
  ],
);

const _cooler = SectionDef(
  id: 'cooler',
  title: '냉방기',
  repeatable: true,
  max: 6,
  rows: [
    RowDef(photo: '냉방기 용량(RT)', fields: [
      FieldDef('냉방기 용량', type: FieldType.choice, options: _coolerRT),
    ]),
  ],
);

const _halon = SectionDef(
  id: 'halon',
  title: '하론',
  repeatable: true,
  max: 6,
  rows: [
    RowDef(photo: '하론 용량', fields: [
      FieldDef('하론 용량', type: FieldType.choice, options: _halonKg),
    ]),
  ],
);

const _backhaul = SectionDef(
  id: 'backhaul',
  title: '백홀',
  rows: [
    RowDef(photo: '백홀장비 제조사', fields: [
      FieldDef('백홀장비 제조사', type: FieldType.choice, options: ['시스코', '화웨이']),
    ]),
    RowDef(photo: '백홀포트 사진'),
  ],
);

const _etc = SectionDef(
  id: 'etc',
  title: '기타',
  rows: [
    RowDef(photo: '기타사진', fields: [
      FieldDef('추가내용', type: FieldType.memo),
    ]),
  ],
);

// ---------------- 4G : 정류기(최대 4) 안에 축전지(최대 6) ----------------
const _battery4G = SectionDef(
  id: 'battery',
  title: '축전지',
  repeatable: true,
  max: 6,
  rows: [
    RowDef(photo: '축전지 타입', fields: [
      FieldDef('축전지 타입', type: FieldType.cascade, cascade: _leadFirst),
    ]),
    RowDef(fields: [_batteryQty]), // 사진 없이 입력만
    RowDef(photo: '정류기 AC직류분전반', fields: [_breaker]),
  ],
);

const _rectifier4G = SectionDef(
  id: 'rectifier',
  title: '정류기',
  repeatable: true,
  max: 4,
  rows: [
    RowDef(photo: '정류기', fields: [FieldDef('정류기명')]),
    // 모델/부하/모듈수량은 사진 없이 입력만
    RowDef(fields: [
      FieldDef('정류기 모델', type: FieldType.choice, options: _models4G),
    ]),
    RowDef(fields: [_load]),
    RowDef(fields: [_modules]),
  ],
  children: [_battery4G],
);

const List<SectionDef> _sections4G = [
  _rectifier4G,
  _cooler,
  _halon,
  _backhaul,
  _etc,
];

// ---------------- 5G : 정류기 1개, IPD(Fuse 추가), 축전지/냉방기/하론 추가 ----------------
const _fuse = SectionDef(
  id: 'fuse',
  title: 'Fuse',
  repeatable: true,
  max: 8,
  rows: [
    RowDef(photo: 'Fuse 번호 / 용량', fields: [
      FieldDef('Fuse 번호', type: FieldType.fuse, options: ['FA', 'FB']),
      FieldDef('Fuse 용량', type: FieldType.choice, options: ['100A', '160A', '200A']),
    ]),
  ],
);

const _ipd = SectionDef(
  id: 'ipd',
  title: 'IPD',
  rows: [
    RowDef(photo: 'IPD', fields: [FieldDef('IPD명')]),
    RowDef(photo: "A'side , B'side 부하", fields: [
      FieldDef("A'side 부하", type: FieldType.number, suffix: 'A'),
      FieldDef("B'side 부하", type: FieldType.number, suffix: 'A'),
    ]),
  ],
  children: [_fuse],
);

const _battery5G = SectionDef(
  id: 'battery',
  title: '축전지',
  repeatable: true,
  max: 6,
  rows: [
    RowDef(photo: '축전지 타입', fields: [
      FieldDef('축전지 타입', type: FieldType.cascade, cascade: _lithiumFirst),
    ]),
    RowDef(fields: [_batteryQty]), // 사진 없이 입력만
  ],
);

const _rectifierRows5G = [
  RowDef(photo: '정류기', fields: [FieldDef('정류기명')]),
  // 모델/부하/모듈수량은 사진 없이 입력만
  RowDef(fields: [
    FieldDef('정류기 모델', type: FieldType.choice, options: _models5G),
  ]),
  RowDef(fields: [_load]),
  RowDef(fields: [_modules]),
  RowDef(photo: '정류기 메인차단기 용량', fields: [_breaker]),
];

const _rectifier5GFloor = SectionDef(
  id: 'rectifier',
  title: '정류기',
  rows: _rectifierRows5G,
);

const _rectifier5GPower = SectionDef(
  id: 'rectifier',
  title: '정류기',
  note: '입전정류기만 해당',
  rows: _rectifierRows5G,
);

// ------------------------------------------------------------
// 확인필요사항
// ------------------------------------------------------------
const _gps = CheckDef('GPS', [
  FieldDef('GPS', type: FieldType.choice, options: _reuseOrAdd),
  FieldDef('케이블길이',
      type: FieldType.number, suffix: 'm', showIfIndex: 0, showIfValue: '증설필요'),
  FieldDef('추가내용'),
]);
const _patch = CheckDef('층간패치', [
  FieldDef('층간패치', type: FieldType.choice, options: _reuseOrAdd),
  FieldDef('추가내용'),
]);
const _pdp = CheckDef('PDP증설', [_type, _qty]);

const _cBackhaulCore = CheckDef('백홀다심', [_len, _qty]);
const _cDuCore = CheckDef('DU다심', [_len, _qty]);
const _cPower = CheckDef('전원선길이', [
  FieldDef('전원선길이', type: FieldType.number, suffix: 'm'),
]);
const _cBlank = CheckDef('BLANK', [_qty]);
const _cSfp = CheckDef('백홀SFP', [_type, _qty]);
const _cVent = CheckDef('배풍구', [_qty]);
const _cSubrack = CheckDef('서브랙', [_qty]);

// ------------------------------------------------------------
// 4가지 분류
// ------------------------------------------------------------
const tplFloor4G = SurveyTemplate(
  id: 'floor_4g',
  place: '상면',
  tech: '4G',
  rack: '신규랙(증설)',
  sections: [_rack, ..._sections4G],
  checks: [
    _cBackhaulCore, _cDuCore, _cPower, _cBlank, _cSfp, _cVent, _cSubrack,
    _gps, _patch, _pdp,
  ],
);

const tplFloor5G = SurveyTemplate(
  id: 'floor_5g',
  place: '상면',
  tech: '5G',
  rack: '신규랙(증설)',
  sections: [
    // 5G 는 냉방기·하론 불필요 (2026-10-27)
    _rack, _rectifier5GFloor, _ipd, _battery5G, _backhaul, _etc,
  ],
  checks: [
    _cBackhaulCore, _cDuCore, _cPower, _cBlank, _cSfp, _cVent, _cSubrack,
    _patch, _pdp, // GPS 는 4G 만
  ],
);

const tplPower4G = SurveyTemplate(
  id: 'power_4g',
  place: '입전',
  tech: '4G',
  rack: '기존랙',
  sections: _sections4G,
  checks: [_cBackhaulCore, _cDuCore, _cBlank, _cSfp, _gps, _patch, _pdp],
);

const tplPower5G = SurveyTemplate(
  id: 'power_5g',
  place: '입전',
  tech: '5G',
  rack: '기존랙',
  sections: [
    // 5G 는 냉방기·하론 불필요 (2026-10-27)
    _rectifier5GPower, _ipd, _battery5G, _backhaul, _etc,
  ],
  checks: [
    _cBackhaulCore, _cDuCore, _cBlank, _cSfp,
    CheckDef('DS판넬', [_qty]),
    CheckDef('LS판넬', [_qty]),
    _patch, _pdp,
  ],
);

const List<SurveyTemplate> kSurveyTemplates = [
  tplFloor4G,
  tplFloor5G,
  tplPower4G,
  tplPower5G,
];

SurveyTemplate? templateById(String id) {
  for (final t in kSurveyTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
