import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// ==========================================
// 1. 메인 리스트 화면 (ProcessScreen)
// ==========================================
class ProcessScreen extends StatefulWidget {
  const ProcessScreen({super.key});

  @override
  State<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends State<ProcessScreen> {
  List<dynamic> _allData = [];
  List<dynamic> _filteredData = [];
  bool _isLoading = true;

  // ★ [수정] 점수 기반 권한 변수
  int _myScore = 0;
  bool _canEdit = false; // 3점 이상일 때만 true

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkUserScore(); // 레벨 대신 점수 확인
  }

  // ★ [핵심 변경] DB에서 'process' 점수 가져오기
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
            // access_scores 맵에서 'process' 점수를 가져옴 (없으면 0점)
            Map<String, dynamic> scores = doc.data()!['access_scores'] ?? {};
            _myScore = scores['process'] ?? 0;

            // 3점 이상일 때만 수정/저장 가능
            _canEdit = _myScore >= 3;
          });
        }
      }
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('Sheet2Data')
          .doc('List')
          .get();

      if (docSnap.exists && docSnap.data() != null) {
        String jsonString = docSnap.data()!['list'] ?? "[]";
        if (!jsonString.trim().startsWith("[")) jsonString = "[$jsonString]";

        List<dynamic> parsedList = jsonDecode(jsonString);
        // 최신순 정렬 (역순)
        parsedList = parsedList.reversed.toList();

        setState(() {
          _allData = parsedList;
          _filteredData = parsedList;
        });
      }
    } catch (e) {
      print("데이터 로드 오류: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _filteredData = _allData);
    } else {
      setState(() {
        _filteredData = _allData.where((item) {
          String local = item['local']?.toString() ?? "";
          String content = item['content']?.toString() ?? "";
          return local.contains(keyword) || content.contains(keyword);
        }).toList();
      });
    }
  }

  void _navigateToDetail(Map<String, dynamic>? item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProcessDetailScreen(
          item: item,
          canEdit: _canEdit, // 3점 여부 전달
          onSave: (newData, oldData) => _saveData(newData, oldData),
        ),
      ),
    );
    _loadData();
  }

  Future<void> _saveData(
      Map<String, dynamic> newData, Map<String, dynamic>? oldData) async {
    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('Sheet2Data')
          .doc('List')
          .get();
      List<dynamic> currentList = [];

      if (docSnap.exists) {
        String jsonString = docSnap.data()!['list'] ?? "[]";
        if (!jsonString.trim().startsWith("[")) jsonString = "[$jsonString]";
        currentList = jsonDecode(jsonString);
      }

      if (oldData == null) {
        currentList.add(newData);
      } else {
        int index = currentList.indexWhere((e) =>
            e['local'] == oldData['local'] &&
            e['date'] == oldData['date'] &&
            e['content'] == oldData['content'] &&
            e['hist'] == oldData['hist']);

        if (index != -1) {
          currentList[index] = newData;
        } else {
          currentList.add(newData);
        }
      }

      String newJsonString = jsonEncode(currentList);
      await FirebaseFirestore.instance
          .collection('Sheet2Data')
          .doc('List')
          .set({'list': newJsonString});

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("저장되었습니다.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("저장 실패: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("진행 내역"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () => _navigateToDetail(null),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              controller: _searchController,
              onChanged: _runFilter,
              decoration: const InputDecoration(
                labelText: '국소명 또는 내용 검색',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredData.isEmpty
                    ? const Center(child: Text("등록된 내역이 없습니다."))
                    : ListView.builder(
                        itemCount: _filteredData.length,
                        itemBuilder: (context, index) {
                          final item = _filteredData[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: ListTile(
                              leading: const Icon(Icons.description,
                                  color: Colors.indigo),
                              title: Text(
                                item['local'] ?? "이름 없음",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['content'] ?? "-",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${item['date']} | ${item['parent']}",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                              onTap: () => _navigateToDetail(item),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 상세 화면 (ProcessDetailScreen)
// ==========================================
class ProcessDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? item;
  final bool canEdit;
  final Function(Map<String, dynamic>, Map<String, dynamic>?) onSave;

  const ProcessDetailScreen({
    super.key,
    this.item,
    required this.canEdit,
    required this.onSave,
  });

  @override
  State<ProcessDetailScreen> createState() => _ProcessDetailScreenState();
}

class _ProcessDetailScreenState extends State<ProcessDetailScreen> {
  late TextEditingController dateCtrl;
  late TextEditingController localCtrl;
  late TextEditingController parentCtrl;
  late TextEditingController contentCtrl;
  late TextEditingController reqCtrl;
  late TextEditingController histCtrl;
  late TextEditingController etcCtrl;

  @override
  void initState() {
    super.initState();
    Map<String, dynamic> data = widget.item ??
        {
          "date": DateFormat('MM월 dd일').format(DateTime.now()),
          "local": "",
          "parent": "",
          "content": "",
          "req": "",
          "hist": "",
          "etc": "",
        };

    dateCtrl = TextEditingController(text: data['date']);
    localCtrl = TextEditingController(text: data['local']);
    parentCtrl = TextEditingController(text: data['parent']);
    contentCtrl = TextEditingController(text: data['content']);
    reqCtrl = TextEditingController(text: data['req']);
    histCtrl = TextEditingController(text: data['hist']);
    etcCtrl = TextEditingController(text: data['etc']);
  }

  @override
  void dispose() {
    dateCtrl.dispose();
    localCtrl.dispose();
    parentCtrl.dispose();
    contentCtrl.dispose();
    reqCtrl.dispose();
    histCtrl.dispose();
    etcCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final newData = {
      "date": dateCtrl.text,
      "local": localCtrl.text,
      "parent": parentCtrl.text,
      "content": contentCtrl.text,
      "req": reqCtrl.text,
      "hist": histCtrl.text,
      "etc": etcCtrl.text,
    };

    widget.onSave(newData, widget.item);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    bool isReadOnly = !widget.canEdit;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? "새 항목 추가" : "상세 정보"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (widget.canEdit)
            TextButton(
              onPressed: _submit,
              child: const Text("저장",
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInputField("날짜", dateCtrl, isReadOnly),
            _buildInputField("국소명", localCtrl, isReadOnly),
            _buildInputField("모국", parentCtrl, isReadOnly),
            _buildInputField("내용", contentCtrl, isReadOnly, maxLines: 5),
            _buildInputField("필요사항", reqCtrl, isReadOnly),
            _buildInputField("내역", histCtrl, isReadOnly),
            _buildInputField("기타", etcCtrl, isReadOnly),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(
      String label, TextEditingController ctrl, bool readOnly,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.indigo)),
          const SizedBox(height: 5),
          TextField(
            controller: ctrl,
            readOnly: readOnly,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.black, fontSize: 16),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: readOnly ? Colors.grey[50] : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                    color: readOnly ? Colors.grey.shade300 : Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
