import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _scheduleItems = [];
  bool _isLoading = true;
  bool _isSaving = false;

  int _myScore = 0;
  bool _canEdit = false;
  bool _canCapture = false;

  DateTime? _score1LimitDate;

  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initScheduleList();
    _checkUserScore();
  }

  void _initScheduleList() {
    _scheduleItems = List.generate(
      14,
      (index) => {"text": "", "name": "", "bg": 16777215, "font": 0},
    );
  }

  Future<void> _checkUserScore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            Map<String, dynamic> scores = doc.data()!['access_scores'] ?? {};
            _myScore = scores['schedule'] ?? 0;
            _canEdit = _myScore >= 3;
            _canCapture = _myScore >= 3;
          });

          if (_myScore == 0) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text("🔒 권한 필요"),
                content: const Text("이 메뉴에 접근할 권한이 없습니다.\n관리자에게 문의하세요."),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text("확인"))
                ],
              ),
            );
            return;
          }

          if (_myScore == 1) {
            _calculateLimitDate();
          } else {
            _loadData();
          }
        }
      }
    } else {
      _loadData();
    }
  }

  Future<void> _calculateLimitDate() async {
    setState(() => _isLoading = true);
    DateTime checkDate = DateTime.now();
    int foundCount = 0;
    int maxSearchDays = 30;

    for (int i = 0; i < maxSearchDays; i++) {
      String dId = DateFormat('yyyy-MM-dd').format(checkDate);
      try {
        final snap = await FirebaseFirestore.instance
            .collection('CalendarData')
            .doc(dId)
            .get();
        bool hasData = false;
        if (snap.exists && snap.data() != null) {
          List<dynamic> items = snap.data()!['items'];
          for (var item in items) {
            String txt = item['text']?.toString().trim() ?? "";
            String nm = item['name']?.toString().trim() ?? "";
            if (txt.isEmpty && nm.isEmpty) break;
            hasData = true;
            break;
          }
        }
        if (hasData) foundCount++;
        if (foundCount >= 3) {
          _score1LimitDate =
              DateTime(checkDate.year, checkDate.month, checkDate.day);
          break;
        }
      } catch (e) {
        print("한계일 계산 중 오류: $e");
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }
    if (_score1LimitDate == null) {
      _score1LimitDate =
          DateTime(checkDate.year, checkDate.month, checkDate.day);
    }
    if (mounted) _loadData();
  }

  String get _dateId => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _displayDate =>
      DateFormat('MM월 dd일 (E)', 'ko_KR').format(_selectedDate);

  Future<void> _loadData() async {
    DateTime current =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);

    bool isLocked = false;

    if (_myScore == 1 && _score1LimitDate != null) {
      if (current.isAfter(_score1LimitDate!) ||
          current.isBefore(today.subtract(const Duration(days: 1)))) {
        isLocked = true;
      }
    } else if (_myScore == 2) {
      DateTime limit7Days = today.add(const Duration(days: 7));
      if (current.isAfter(limit7Days) ||
          current.isBefore(today.subtract(const Duration(days: 1)))) {
        isLocked = true;
      }
    }

    if (isLocked) {
      setState(() {
        _scheduleItems = List.generate(
            14,
            (i) =>
                {"text": "🔒 권한 없음", "name": "-", "bg": 16777215, "font": 0});
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('CalendarData')
          .doc(_dateId)
          .get();

      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        if (data.containsKey('items')) {
          List<dynamic> loadedItems = data['items'];
          for (int i = 0; i < 14; i++) {
            if (i < loadedItems.length) {
              String originalText = loadedItems[i]['text'] ?? "";
              String originalName = loadedItems[i]['name'] ?? "";

              _scheduleItems[i] = {
                "text": originalText,
                "name": originalName,
                "bg": loadedItems[i]['bg'] ?? 16777215,
                "font": loadedItems[i]['font'] ?? 0,
              };
            } else {
              _scheduleItems[i] = {
                "text": "",
                "name": "",
                "bg": 16777215,
                "font": 0
              };
            }
          }
        }
      } else {
        _initScheduleList();
      }
    } catch (e) {
      print("에러: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveData() async {
    if (!_canEdit) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('CalendarData')
          .doc(_dateId)
          .set({'dateID': _dateId, 'items': _scheduleItems});
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("저장되었습니다.")));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("저장 실패: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadData();
  }

  void _goToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadData();
  }

  void _onHorizontalDrag(DragEndDetails details) {
    if (details.primaryVelocity! > 0) {
      _changeDate(-1);
    } else if (details.primaryVelocity! < 0) {
      _changeDate(1);
    }
  }

  Future<void> _showWeeklyPopup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> weeklyData = [];
    DateTime checkDate = DateTime.now();

    int foundCount = 0;
    int searchedDays = 0;

    int targetCount = (_myScore == 1) ? 3 : 7;
    int maxSearchDays = (_myScore == 1) ? 30 : 7;

    while (searchedDays < maxSearchDays) {
      if (_myScore == 1 && foundCount >= targetCount) break;

      String dId = DateFormat('yyyy-MM-dd').format(checkDate);
      String dLabel = DateFormat('MM월 dd일 (E)', 'ko_KR').format(checkDate);

      try {
        final snap = await FirebaseFirestore.instance
            .collection('CalendarData')
            .doc(dId)
            .get();

        List<Map<String, dynamic>> validItems = [];
        bool hasDataToday = false;

        if (snap.exists && snap.data() != null) {
          List<dynamic> items = snap.data()!['items'];
          for (var item in items) {
            String txt = item['text'] ?? "";
            String nm = item['name'] ?? "";
            if (txt.trim().isEmpty && nm.trim().isEmpty) {
              break;
            }
            item['text'] = txt;
            validItems.add(item);
            hasDataToday = true;
          }
        }

        if (_myScore == 1) {
          if (hasDataToday) {
            weeklyData
                .add({'date': checkDate, 'label': dLabel, 'items': validItems});
            foundCount++;
          }
        } else {
          weeklyData
              .add({'date': checkDate, 'label': dLabel, 'items': validItems});
        }
      } catch (e) {
        print(e);
      }

      checkDate = checkDate.add(const Duration(days: 1));
      searchedDays++;
    }

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_myScore == 1
            ? "📅 예정된 일정 (3일치)"
            : (_myScore == 2 ? "📅 주간 일정 (7일)" : "📅 주간 일정")),
        content: SizedBox(
          width: double.maxFinite,
          child: weeklyData.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20), child: Text("예정된 일정이 없습니다."))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: weeklyData.length,
                  itemBuilder: (context, index) {
                    final day = weeklyData[index];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _selectedDate = day['date']);
                        _loadData();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        color: Colors.grey.shade100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(day['label'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo)),
                            if (day['items'].isEmpty)
                              const Text("- 일정 없음 -",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey))
                            else
                              ...day['items'].map<Widget>((item) {
                                String t = item['text'] ?? "";
                                String n = item['name'] ?? "";
                                String displayStr =
                                    n.trim().isEmpty ? t : "$t ($n)";
                                return Text(
                                  displayStr,
                                  style: const TextStyle(color: Colors.black),
                                );
                              }).toList(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("닫기"))
        ],
      ),
    );
  }

  void _showTaskOptions(int index) {
    if (!_canEdit) return;
    final item = _scheduleItems[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("일정 관리"),
        content: Text("선택한 일정:\n${item['text']}"),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showEditDialog(index);
              },
              child: const Text("수정")),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _moveTaskStart(index);
              },
              child: const Text("이동", style: TextStyle(color: Colors.orange))),
          TextButton(
              onPressed: () {
                setState(() => _scheduleItems[index] = {
                      "text": "",
                      "name": "",
                      "bg": 16777215,
                      "font": 0
                    });
                Navigator.pop(ctx);
                _saveData();
              },
              child: const Text("삭제", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _showEditDialog(int index) {
    TextEditingController textCtrl =
        TextEditingController(text: _scheduleItems[index]['text']);
    TextEditingController nameCtrl =
        TextEditingController(text: _scheduleItems[index]['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("일정 수정"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: textCtrl,
                decoration: const InputDecoration(labelText: "내용"),
                maxLines: 2),
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "담당자")),
          ],
        ),
        actions: [
          ElevatedButton(
              onPressed: () {
                setState(() {
                  _scheduleItems[index]['text'] = textCtrl.text;
                  _scheduleItems[index]['name'] = nameCtrl.text;
                });
                Navigator.pop(ctx);
                _saveData();
              },
              child: const Text("저장")),
        ],
      ),
    );
  }

  Future<void> _moveTaskStart(int srcIndex) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: "이동할 날짜 선택",
    );

    if (pickedDate != null) {
      _moveTaskSelectSlot(srcIndex, pickedDate);
    }
  }

  Future<void> _moveTaskSelectSlot(int srcIndex, DateTime targetDate) async {
    String targetId = DateFormat('yyyy-MM-dd').format(targetDate);
    List<Map<String, dynamic>> targetItems = List.generate(
        14, (i) => {"text": "", "name": "", "bg": 16777215, "font": 0});

    if (targetId == _dateId) {
      targetItems = List.from(_scheduleItems);
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final snap = await FirebaseFirestore.instance
            .collection('CalendarData')
            .doc(targetId)
            .get();
        if (snap.exists && snap.data() != null) {
          List<dynamic> list = snap.data()!['items'];
          for (int i = 0; i < 14 && i < list.length; i++) {
            targetItems[i] = {
              "text": list[i]['text'] ?? "",
              "name": list[i]['name'] ?? "",
              "bg": list[i]['bg'] ?? 16777215,
              "font": list[i]['font'] ?? 0,
            };
          }
        }
      } catch (e) {
        Navigator.pop(context);
        return;
      }
      Navigator.pop(context);
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${DateFormat('MM월 dd일').format(targetDate)} 위치 선택"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: 14,
            itemBuilder: (ctx, i) {
              bool isEmpty = targetItems[i]['text'].toString().isEmpty;
              return ListTile(
                title: Text(
                  isEmpty ? "(빈칸)" : targetItems[i]['text'],
                  style: TextStyle(color: isEmpty ? Colors.grey : Colors.black),
                ),
                onTap: () async {
                  if (!isEmpty) {
                    bool? ok = await showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text("경고"),
                        content: const Text("기존 일정을 덮어쓰시겠습니까?"),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text("취소")),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text("덮어쓰기")),
                        ],
                      ),
                    );
                    if (ok != true) return;
                  }
                  Navigator.pop(ctx);
                  _executeMove(srcIndex, targetId, targetItems, i);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
        ],
      ),
    );
  }

  Future<void> _executeMove(int srcIndex, String targetId,
      List<Map<String, dynamic>> targetList, int targetIndex) async {
    Map<String, dynamic> dataToMove = Map.from(_scheduleItems[srcIndex]);

    if (targetId == _dateId) {
      setState(() {
        _scheduleItems[targetIndex] = dataToMove;
        _scheduleItems[srcIndex] = {
          "text": "",
          "name": "",
          "bg": 16777215,
          "font": 0
        };
      });
      await _saveData();
    } else {
      targetList[targetIndex] = dataToMove;
      await FirebaseFirestore.instance
          .collection('CalendarData')
          .doc(targetId)
          .set({'dateID': targetId, 'items': targetList});

      setState(() {
        _scheduleItems[srcIndex] = {
          "text": "",
          "name": "",
          "bg": 16777215,
          "font": 0
        };
      });
      await _saveData();
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("이동 완료!")));
  }

  Future<void> _captureAndShare() async {
    try {
      RenderRepaintBoundary boundary = _captureKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      final directory = await getApplicationDocumentsDirectory();
      final imagePath =
          await File('${directory.path}/schedule_capture.png').create();
      await imagePath.writeAsBytes(pngBytes);
      await Share.shareXFiles([XFile(imagePath.path)],
          text: '$_displayDate 일정');
    } catch (e) {
      print("캡처 실패: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    int captureCount = 0;
    for (int i = 0; i < 14; i++) {
      bool hasText = _scheduleItems[i]['text'].toString().trim().isNotEmpty;
      bool hasName = _scheduleItems[i]['name'].toString().trim().isNotEmpty;
      if (hasText || hasName) {
        captureCount++;
      } else {
        break;
      }
    }
    if (captureCount < 5) captureCount = 5;

    int viewCount = 14;
    if (_myScore == 1) {
      viewCount = captureCount;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("팀 일정 관리"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_canEdit)
            TextButton(
                onPressed: _isSaving ? null : _saveData,
                child: const Text("저장",
                    style: TextStyle(color: Colors.white, fontSize: 16))),
        ],
      ),
      body: Stack(
        children: [
          // 캡처용 위젯
          Transform.translate(
            offset: const Offset(-9999, -9999),
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFCCFFFF),
                          border: Border(
                              bottom:
                                  BorderSide(color: Colors.black, width: 1.0)),
                        ),
                        alignment: Alignment.center,
                        child: Text(_displayDate,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: captureCount,
                        itemBuilder: (context, index) =>
                            _buildScheduleRow(index, isForCapture: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 메인 화면
          Column(
            children: [
              Container(
                color: Colors.grey[100],
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: () => _changeDate(-1)),
                    ElevatedButton(
                        onPressed: _goToday, child: const Text("오늘")),
                    ElevatedButton(
                        onPressed: _showWeeklyPopup, child: const Text("주간")),
                    IconButton(
                        icon: const Icon(Icons.arrow_forward_ios),
                        onPressed: () => _changeDate(1)),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFFCCFFFF),
                    border: Border.all(width: 1.0)),
                alignment: Alignment.center,
                child: Text(_displayDate,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragEnd: _onHorizontalDrag,
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        ...List.generate(viewCount, (index) {
                          return Expanded(
                            child:
                                _buildScheduleRow(index, isForCapture: false),
                          );
                        }),
                        if (viewCount < 14) Spacer(flex: 14 - viewCount),
                      ],
                    ),
                  ),
                ),
              ),
              if (_canCapture)
                SafeArea(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF28a745),
                          padding: const EdgeInsets.symmetric(vertical: 15)),
                      onPressed: _captureAndShare,
                      child: const Text("캡처 및 공유",
                          style: TextStyle(color: Colors.white, fontSize: 18)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ★ [핵심 변경] 레이아웃 로직이 변경된 함수
  Widget _buildScheduleRow(int index, {required bool isForCapture}) {
    String textVal = _scheduleItems[index]['text'].toString();
    String nameVal = _scheduleItems[index]['name'].toString();

    // 내용과 담당자 중 하나라도 있으면 컨텐츠가 있는 것으로 간주
    bool hasContent = textVal.isNotEmpty || nameVal.isNotEmpty;

    // 담당자가 있는지 확인 (공백 제거 후 판단)
    bool hasManager = nameVal.trim().isNotEmpty;

    return GestureDetector(
      onTap: () {
        if (isForCapture) return;
        if (!_canEdit) return;
        if (hasContent)
          _showTaskOptions(index);
        else
          _showEditDialog(index);
      },
      child: Container(
        padding: isForCapture
            ? const EdgeInsets.symmetric(vertical: 4, horizontal: 8)
            : const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: null,
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            // ★ [경우 1] 담당자가 있는 경우: 기존처럼 분할 (하지만 담당자 칸을 좁게)
            if (hasManager) ...[
              Expanded(
                child: Text(
                  textVal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: isForCapture ? 16 : 15, color: Colors.black),
                ),
              ),
              const SizedBox(width: 8), // 간격
              // 담당자 칸 너비를 고정값으로 줄임 (약 80px, 글자수 5자 고려)
              SizedBox(
                width: isForCapture ? 90 : 80,
                child: Text(
                  nameVal,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: isForCapture ? 15 : 14, color: Colors.black),
                ),
              ),
            ]
            // ★ [경우 2] 담당자가 없는 경우: 내용만 전체 너비로 표시
            else ...[
              Expanded(
                child: Text(
                  textVal,
                  // overflow: TextOverflow.ellipsis를 제거하여 전체 내용 표시
                  style: TextStyle(
                      fontSize: isForCapture ? 16 : 15, color: Colors.black),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
