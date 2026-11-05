import 'package:flutter/material.dart';

// ============================================================
// 임시저장 / 완료 기록 목록 (실사·개통 공통)
//  - 첫 화면에는 [임시저장 N건] [완료한 개통 N건] 버튼만
//  - 누르면 아래에서 목록이 올라옴: 국소명 검색, 최근 순, 날짜별 묶음
//  - 삭제는 휴지통 → 확인창(onDelete 가 true 를 돌려줄 때만 목록에서 뺌)
// ============================================================

class RecordEntry {
  final String station; // 국소명 (여러 줄 가능)
  final String sub; // 아래 작은 글 (장비 · 시각 · 사진 N장)
  final DateTime at;
  final String action; // '이어서' / '불러오기'
  final Future<void> Function() onOpen;
  final Future<bool> Function() onDelete;

  RecordEntry({
    required this.station,
    required this.sub,
    required this.at,
    required this.action,
    required this.onOpen,
    required this.onDelete,
  });
}

String recordTitle(String station) {
  final l = station.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  if (l.isEmpty) return '';
  return l.length > 1 ? '${l.first} 외 ${l.length - 1}' : l.first;
}

/// 첫 화면의 큰 버튼 (건수 없으면 회색, 눌러도 반응 없음)
class RecordCountButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final String hint;
  final Color bg;
  final Color border;
  final Color fg;
  final VoidCallback onTap;

  const RecordCountButton({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.hint,
    required this.bg,
    required this.border,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    final c = on ? fg : const Color(0xFF9AA0B4);
    return Material(
      color: on ? bg : const Color(0xFFF5F6F8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? border : const Color(0xFFE3E5EC)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: on ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(icon, size: 17, color: c),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c)),
                ),
              ]),
              Text('$count건', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c, height: 1.25)),
              Text(on ? hint : '없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 목록 시트 열기. title 은 남은 건수를 받아 제목을 만듦 (삭제하면 바로 바뀜)
Future<void> showRecordListSheet(
  BuildContext context, {
  required String Function(int count) title,
  required String sub,
  required Color color,
  required List<RecordEntry> entries,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RecordListSheet(title: title, sub: sub, color: color, entries: entries),
  );
}

class _RecordListSheet extends StatefulWidget {
  final String Function(int count) title;
  final String sub;
  final Color color;
  final List<RecordEntry> entries;

  const _RecordListSheet({required this.title, required this.sub, required this.color, required this.entries});

  @override
  State<_RecordListSheet> createState() => _RecordListSheetState();
}

class _RecordListSheetState extends State<_RecordListSheet> {
  late final List<RecordEntry> _list = List.of(widget.entries)..sort((a, b) => b.at.compareTo(a.at));
  String _q = '';

  static String _norm(String s) => s.replaceAll(RegExp(r'\s'), '').toLowerCase();

  static String _day(DateTime t) {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final diff = d0.difference(d).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${t.month}월 ${t.day}일';
  }

  @override
  Widget build(BuildContext context) {
    final q = _norm(_q);
    final shown = _list.where((e) => q.isEmpty || _norm(e.station).contains(q)).toList();
    final mq = MediaQuery.of(context);
    // 아래 여백: 키보드가 올라오면 키보드 높이, 아니면 휴대폰 아래 버튼 줄 높이만큼
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.viewPadding.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.82),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 6, 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title(_list.length),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.color)),
                    const SizedBox(height: 2),
                    Text(widget.sub, style: const TextStyle(fontSize: 12, color: Color(0xFF5F6473))),
                  ]),
                ),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, color: Color(0xFF5F6473)),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (s) => setState(() => _q = s),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '국소명 검색',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF7F8FB),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFF9AA0B4))),
                ),
              ),
            ),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text("'$_q' 이(가) 들어간 국소가 없어요",
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF5F6473))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 8, 20),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final e = shown[i];
                        final day = _day(e.at);
                        final head = i == 0 || _day(shown[i - 1].at) != day;
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (head)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Text(day,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5F6473))),
                            ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFECEEF3)))),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(recordTitle(e.station),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  Text(e.sub, style: const TextStyle(fontSize: 12, color: Color(0xFF5F6473))),
                                ]),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await e.onOpen();
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3F51B5), foregroundColor: Colors.white, shape: const StadiumBorder()),
                                child: Text(e.action),
                              ),
                              IconButton(
                                tooltip: '삭제',
                                icon: const Icon(Icons.delete_outline, color: Color(0xFF9E9E9E)),
                                onPressed: () async {
                                  final ok = await e.onDelete();
                                  if (!ok || !mounted) return;
                                  setState(() => _list.remove(e));
                                  if (_list.isEmpty && context.mounted) Navigator.pop(context);
                                },
                              ),
                            ]),
                          ),
                        ]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
