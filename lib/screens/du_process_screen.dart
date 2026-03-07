import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// [수정됨] 엑셀 열 추가로 인한 Key 변경 (g -> i, i -> k ...)
const Map<String, String> kColHeaders = {
  'i': '상면검토',
  'k': '입전검토',
  'm': 'ID할당',
  'o': 'IP할당',
  'q': 'MME등록',
  's': 'SAC특번',
  'u': 'ADD/E1/IP',
};

class DuProcessScreen extends StatefulWidget {
  const DuProcessScreen({super.key});

  @override
  State<DuProcessScreen> createState() => _DuProcessScreenState();
}

class _DuProcessScreenState extends State<DuProcessScreen> {
  List<dynamic> _allData = [];
  List<dynamic> _filteredData = [];
  bool _isLoading = true;

  int _myScore = 0;
  bool _canEdit = false;

  final TextEditingController _searchController = TextEditingController();

  static const int colRedText = 192;
  static const int colBlueText = 6299648;

  @override
  void initState() {
    super.initState();
    _checkUserScore();
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
            _myScore = scores['du_process'] ?? 0;
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
          .collection('Sheet3Data')
          .doc('List')
          .get();

      if (docSnap.exists && docSnap.data() != null) {
        String jsonString = docSnap.data()!['list'] ?? "[]";
        if (!jsonString.trim().startsWith("[")) jsonString = "[$jsonString]";

        List<dynamic> rawList = jsonDecode(jsonString);
        List<dynamic> processedList = [];

        for (var row in rawList) {
          if (row is! Map<String, dynamic>) continue;
          // 엑셀에서 넘어온 데이터는 모두 표시 (필터링 없음)
          processedList.add(row);
        }

        if (mounted) {
          setState(() {
            _allData = processedList;
            _filteredData = processedList;
          });
        }
      }
    } catch (e) {
      print("오류: $e");
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
          String name = item['du_name']?.toString() ?? "";
          String type = item['du_type']?.toString() ?? "";
          return name.contains(keyword) || type.contains(keyword);
        }).toList();
      });
    }
  }

  Color _parseExcelColor(dynamic colorCode) {
    if (colorCode == null) return Colors.black;
    int code = int.tryParse(colorCode.toString()) ?? 0;
    if (code == colRedText) return Colors.red;
    if (code == colBlueText) return Colors.blue;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("DU 진행"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DuDetailScreen(
                      item: null,
                      canEdit: _canEdit,
                    ),
                  ),
                );
                _loadData();
              },
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
                labelText: '국소명 검색',
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
                    ? const Center(child: Text("표시할 내역이 없습니다."))
                    : ListView.builder(
                        itemCount: _filteredData.length,
                        itemBuilder: (context, index) {
                          final item = _filteredData[index];

                          String title = item['du_name']?.toString() ?? "이름 없음";
                          String type = item['du_type']?.toString() ?? "";
                          String code = item['code']?.toString() ?? "";
                          String memo = item['memo']?.toString() ?? "";
                          String incomplete =
                              item['incomplete']?.toString() ?? "";

                          Color titleColor =
                              _parseExcelColor(item['font_color']);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            color: Colors.white,
                            elevation: 2,
                            child: ListTile(
                              title: Text(
                                title,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: titleColor),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 5),
                                  Text(
                                    code.isNotEmpty
                                        ? "$type | Code: $code"
                                        : type,
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 13),
                                  ),
                                  if (memo.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text("📝 $memo",
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87)),
                                    ),
                                  const SizedBox(height: 8),

                                  // 미비점이 있으면 주황색 박스
                                  if (incomplete.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                              color: Colors.orange.shade200)),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                              Icons.warning_amber_rounded,
                                              size: 16,
                                              color: Colors.deepOrange),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              "미완료: $incomplete",
                                              style: const TextStyle(
                                                color: Colors.deepOrange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    // 미비점 없으면 초록색 '준비완료' 박스
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                              color: Colors.green.shade200)),
                                      child: Row(
                                        children: const [
                                          Icon(Icons.check_circle,
                                              size: 16, color: Colors.green),
                                          SizedBox(width: 5),
                                          Text("모든항목 준비완료",
                                              style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Colors.grey),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DuDetailScreen(
                                      item: item,
                                      canEdit: _canEdit,
                                    ),
                                  ),
                                );
                                _loadData();
                              },
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

// ==================================================================
// 전체 화면 상세 페이지
// ==================================================================
class DuDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? item;
  final bool canEdit;

  const DuDetailScreen({super.key, this.item, required this.canEdit});

  @override
  State<DuDetailScreen> createState() => _DuDetailScreenState();
}

class _DuDetailScreenState extends State<DuDetailScreen> {
  late TextEditingController nameCtrl;
  late TextEditingController typeCtrl;
  late TextEditingController codeCtrl;
  late TextEditingController memoCtrl;

  late Map<String, dynamic> data;
  List<String> incompleteList = [];
  List<String> excludedList = [];

  @override
  void initState() {
    super.initState();
    data = widget.item != null
        ? Map<String, dynamic>.from(widget.item!)
        : {
            "du_name": "",
            "du_type": "",
            "code": "",
            "memo": "",
            "incomplete": "",
            "excluded": "",
            "isAppEntry": true
          };

    nameCtrl = TextEditingController(text: data['du_name']);
    typeCtrl = TextEditingController(text: data['du_type']);
    codeCtrl = TextEditingController(text: data['code']);
    memoCtrl = TextEditingController(text: data['memo']);

    String incompleteStr = data['incomplete']?.toString() ?? "";
    incompleteList = incompleteStr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String excludedStr = data['excluded']?.toString() ?? "";
    excludedList = excludedStr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    typeCtrl.dispose();
    codeCtrl.dispose();
    memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveData() async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('Sheet3Data').doc('List');
      final docSnap = await docRef.get();
      List<dynamic> currentList = [];

      if (docSnap.exists) {
        String jsonString = docSnap.data()!['list'] ?? "[]";
        if (!jsonString.trim().startsWith("[")) jsonString = "[$jsonString]";
        currentList = jsonDecode(jsonString);
      }

      Map<String, dynamic> newData = {
        ...data,
        "du_name": nameCtrl.text,
        "du_type": typeCtrl.text,
        "code": codeCtrl.text,
        "memo": memoCtrl.text,
        "incomplete": incompleteList.join(", "),
      };

      if (widget.item == null) {
        currentList.add(newData);
      } else {
        int index = currentList.indexWhere((e) =>
            e['du_name'] == widget.item!['du_name'] &&
            e['du_type'] == widget.item!['du_type']);

        if (index != -1) {
          Map<String, dynamic> merged = Map.from(currentList[index]);
          merged.addAll(newData);
          currentList[index] = merged;
        } else {
          currentList.add(newData);
        }
      }

      await docRef.set({'list': jsonEncode(currentList)});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("저장되었습니다.")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("저장 실패: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasAnyItemToShow = false;
    for (var label in kColHeaders.values) {
      if (!excludedList.contains(label)) {
        hasAnyItemToShow = true;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? "항목 추가" : "상세 정보"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (widget.canEdit)
            TextButton(
              onPressed: _saveData,
              child: const Text("저장",
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField("DU명", nameCtrl, widget.canEdit),
            _buildTextField("구분", typeCtrl, widget.canEdit),
            _buildTextField("Code", codeCtrl, widget.canEdit),
            _buildTextField("특이사항/메모", memoCtrl, widget.canEdit, maxLines: 3),

            const Divider(height: 40, thickness: 2),
            const Text("📊 진행 상태",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),

            // 상세 화면: 항목이 하나도 없거나(전부 검정), 미비점이 비어있으면 -> 준비완료 표시
            if (!hasAnyItemToShow ||
                (incompleteList.isEmpty && hasAnyItemToShow)) ...[
              if (incompleteList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.check_circle, size: 40, color: Colors.green),
                      SizedBox(height: 10),
                      Text("모든항목 준비완료",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                )
            ],

            ...kColHeaders.entries.map((entry) {
              String key = entry.key;
              String label = entry.value;

              if (excludedList.contains(label)) {
                return const SizedBox.shrink();
              }

              bool isIncomplete = incompleteList.contains(label);
              String savedDate = data['${key}_date'] ?? "";

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isIncomplete
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isIncomplete ? Colors.orange : Colors.green),
                ),
                child: Row(
                  children: [
                    Icon(
                      isIncomplete
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle,
                      color: isIncomplete ? Colors.orange : Colors.green,
                      size: 24,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isIncomplete
                              ? Colors.deepOrange
                              : Colors.green.shade800,
                        ),
                      ),
                    ),
                    if (widget.canEdit) ...[
                      if (isIncomplete)
                        ElevatedButton(
                          onPressed: () async {
                            DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              String dateStr =
                                  DateFormat('MM-dd').format(picked);
                              setState(() {
                                incompleteList.remove(label);
                                data['${key}_date'] = dateStr;
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.deepOrange,
                            elevation: 0,
                            side: const BorderSide(color: Colors.deepOrange),
                          ),
                          child: const Text("입력"),
                        )
                      else
                        Row(
                          children: [
                            InkWell(
                              onTap: () async {
                                DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  String dateStr =
                                      DateFormat('MM-dd').format(picked);
                                  setState(() {
                                    data['${key}_date'] = dateStr;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: Text(
                                  savedDate.isNotEmpty ? savedDate : "완료",
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  incompleteList.add(label);
                                  data.remove('${key}_date');
                                });
                              },
                              child:
                                  const Icon(Icons.refresh, color: Colors.grey),
                            ),
                          ],
                        ),
                    ] else ...[
                      if (!isIncomplete)
                        Text(
                          savedDate.isNotEmpty ? savedDate : "완료",
                          style: const TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold),
                        )
                    ]
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, bool enabled,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.black, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 16),
          border: const OutlineInputBorder(),
          filled: !enabled,
          fillColor: !enabled ? Colors.grey[100] : null,
        ),
      ),
    );
  }
}
