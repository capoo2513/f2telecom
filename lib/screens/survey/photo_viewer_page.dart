import 'dart:io';
import 'package:flutter/material.dart';

// ============================================================
// 사진 크게 보기 (실사·개통 공통)
//  - 입력 화면의 작은 사진을 눌렀을 때 / 밴드 미리보기의 사진을 눌렀을 때 같은 화면
//  - 화면을 좌우로 밀어서 다음·이전 사진, 두 손가락으로 확대
//  - [이 사진 빼기] → 확인창 → onRemove(번호). photos 목록은 부르는 쪽 목록 그대로 씀
//    (onRemove 안에서 부르는 쪽이 photos 에서 빼면 이 화면도 바로 따라감)
// ============================================================
class PhotoViewerPage extends StatefulWidget {
  final List<String> photos;
  final int start;
  final String title; // 맨 위 '제목 2 / 5' 의 제목 (없으면 번호만)
  final String Function(int i)? labelOf; // 사진 위 글자 (밴드에 올릴 때 새기는 글)
  final String Function(int i)? noteOf; // 겹친 사진 표시 ('중복' / '○○에도 있음')
  final String removeMessage;
  final void Function(int index) onRemove;

  const PhotoViewerPage({
    super.key,
    required this.photos,
    required this.start,
    required this.onRemove,
    this.title = '',
    this.labelOf,
    this.noteOf,
    this.removeMessage = '이 사진을 목록에서 뺄까요?\n(휴대폰 갤러리에 저장된 사진은 그대로예요)',
  });

  /// 열기 (부르는 쪽에서 한 줄로)
  static Future<void> open(
    BuildContext context, {
    required List<String> photos,
    required int start,
    required void Function(int index) onRemove,
    String title = '',
    String Function(int i)? labelOf,
    String Function(int i)? noteOf,
    String? removeMessage,
  }) {
    if (photos.isEmpty) return Future.value();
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewerPage(
          photos: photos,
          start: start.clamp(0, photos.length - 1),
          onRemove: onRemove,
          title: title,
          labelOf: labelOf,
          noteOf: noteOf,
          removeMessage: removeMessage ?? '이 사진을 목록에서 뺄까요?\n(휴대폰 갤러리에 저장된 사진은 그대로예요)',
        ),
      ),
    );
  }

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pc = PageController(initialPage: widget.start);
  late int _i = widget.start;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 사진을 뺄까요?'),
        content: Text(widget.removeMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('빼기', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.onRemove(_i);
    if (!mounted) return;
    if (widget.photos.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      if (_i >= widget.photos.length) _i = widget.photos.length - 1;
    });
    if (_pc.hasClients) _pc.jumpToPage(_i);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('사진을 뺐어요'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.photos.length;
    if (n == 0) return const Scaffold(backgroundColor: Colors.black);
    final i = _i.clamp(0, n - 1);
    final label = widget.labelOf?.call(i) ?? '';
    final note = widget.noteOf?.call(i) ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title.isEmpty ? '${i + 1} / $n' : '${widget.title}  ${i + 1} / $n',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: _remove,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            label: const Text('이 사진 빼기', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(children: [
        if (note.isNotEmpty)
          Container(
            width: double.infinity,
            color: note == '중복' ? const Color(0xFFD32F2F) : const Color(0xFFEF6C00),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(note == '중복' ? '같은 칸에 같은 사진이 또 있어요' : '같은 사진이 $note',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        if (label.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('사진 위 글자: $label', style: const TextStyle(color: Colors.amber, fontSize: 13)),
          ),
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: n,
            onPageChanged: (v) => setState(() => _i = v),
            itemBuilder: (_, k) => InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(File(widget.photos[k]), fit: BoxFit.contain)),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text('좌우로 밀어서 넘기기 · 두 손가락으로 확대', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ]),
    );
  }
}
