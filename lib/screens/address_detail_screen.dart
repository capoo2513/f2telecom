import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AddressDetailScreen extends StatefulWidget {
  final String title;
  final String address;
  final String type;
  final String category;
  final String tmapAddress;
  final String specialNote;
  final int userScore; // 내 점수

  const AddressDetailScreen({
    super.key,
    required this.title,
    required this.address,
    required this.type,
    required this.category,
    required this.tmapAddress,
    required this.specialNote,
    required this.userScore,
  });

  @override
  State<AddressDetailScreen> createState() => _AddressDetailScreenState();
}

class _AddressDetailScreenState extends State<AddressDetailScreen> {
  final TextEditingController _memoController = TextEditingController();

  Future<void> _launchTmap() async {
    final String targetAddr =
        widget.tmapAddress.isNotEmpty ? widget.tmapAddress : widget.address;
    final String tmapUrl = "tmap://search?name=$targetAddr";
    final String storeUrl = "market://details?id=com.skt.tmap.ku";
    try {
      if (await canLaunchUrl(Uri.parse(tmapUrl))) {
        await launchUrl(Uri.parse(tmapUrl),
            mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(Uri.parse(storeUrl),
            mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("TMAP 실행 불가")));
    }
  }

  void _copyAddress() {
    final String targetAddr =
        widget.tmapAddress.isNotEmpty ? widget.tmapAddress : widget.address;
    Clipboard.setData(ClipboardData(text: targetAddr));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("주소가 복사되었습니다!")));
  }

  void _addMemo() async {
    if (_memoController.text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String writerEmail = user.email ?? "익명";
    String writerName = "이름없음";

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        writerName = userDoc.data()?['name'] ?? "이름없음";
      }
    } catch (e) {
      print("이름 불러오기 실패: $e");
    }

    try {
      await FirebaseFirestore.instance.collection('station_memos').add({
        'stationName': widget.title,
        'content': _memoController.text,
        'writer': writerEmail,
        'writerName': writerName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _memoController.clear();
      FocusScope.of(context).unfocus();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("메모가 등록되었습니다.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("등록 실패: $e")));
      }
    }
  }

  // 메모 삭제 (3점 관리자만 가능)
  void _deleteMemo(String docId) {
    if (widget.userScore < 3) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("메모 삭제"),
        content: const Text("이 메모를 삭제하시겠습니까?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance
                  .collection('station_memos')
                  .doc(docId)
                  .delete();
              Navigator.pop(ctx);
            },
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★ [핵심 수정] 1점 이상이면 특이사항(specialNote) 전체 공개
    // 0점은 아예 들어오지 못하므로, 들어온 사람은 다 볼 수 있음
    bool showSpecialNote = (widget.userScore >= 1) &&
        (widget.specialNote.isNotEmpty && widget.specialNote != "null");

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("주소: ${widget.address}",
                  style: const TextStyle(fontSize: 16)),
              Text("형태/구분: ${widget.type} / ${widget.category}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 20),

              // 특이사항 표시 (1점 이상이면 보임)
              if (showSpecialNote) ...[
                const Text("⚠ 특이사항",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red)),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 5),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(widget.specialNote),
                ),
                const SizedBox(height: 20),
              ],

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.map, color: Colors.indigo),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("T-map 검색 주소:",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                              Text(
                                widget.tmapAddress.isNotEmpty
                                    ? widget.tmapAddress
                                    : widget.address,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                            onPressed: _copyAddress,
                            icon: const Icon(Icons.copy),
                            tooltip: "복사"),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _launchTmap,
                        icon: const Icon(Icons.navigation),
                        label: const Text("TMAP 길안내"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const Divider(thickness: 2),
              const Text("현장 메모",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // 메모 입력창 (1점 이상이면 누구나 작성 가능)
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: _memoController,
                          decoration: const InputDecoration(
                              hintText: "메모를 남겨주세요",
                              border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _addMemo, child: const Text("등록")),
                ],
              ),
              const SizedBox(height: 10),

              // 메모 리스트
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('station_memos')
                    .where('stationName', isEqualTo: widget.title)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.red[50],
                      child: Text(
                          "데이터 로드 오류: ${snapshot.error}\n(관리자에게 '색인' 생성을 요청하세요)"),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty)
                    return const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text("등록된 메모가 없습니다."));

                  docs.sort((a, b) {
                    Timestamp tA = a['createdAt'] ?? Timestamp.now();
                    Timestamp tB = b['createdAt'] ?? Timestamp.now();
                    return tB.compareTo(tA);
                  });

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final docId = docs[index].id;

                      Timestamp? ts = data['createdAt'];
                      String dateStr = ts != null
                          ? DateFormat('MM/dd HH:mm').format(ts.toDate())
                          : "";

                      String email = data['writer'] ?? '익명';
                      String name = data['writerName'] ?? '';
                      String writerInfo =
                          name.isNotEmpty ? "$name ($email)" : email;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        // 3점(관리자)이면 롱터치로 삭제 가능
                        child: InkWell(
                          onLongPress: widget.userScore >= 3
                              ? () => _deleteMemo(docId)
                              : null,
                          child: ListTile(
                            dense: true,
                            title: Text(data['content'] ?? ""),
                            subtitle: Text("$writerInfo • $dateStr",
                                style: const TextStyle(fontSize: 12)),
                            // 관리자면 쓰레기통 아이콘 표시
                            trailing: widget.userScore >= 3
                                ? IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 18, color: Colors.grey),
                                    onPressed: () => _deleteMemo(docId),
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
