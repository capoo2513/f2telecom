import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AllMemosScreen extends StatelessWidget {
  const AllMemosScreen({super.key});

  // 메모 삭제 함수
  void _deleteMemo(String docId) {
    FirebaseFirestore.instance.collection('station_memos').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("모든 메모 모아보기"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('station_memos')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("오류 발생"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("현재 등록된 현장 메모가 없습니다."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;

              // 날짜 처리
              String dateStr = "";
              if (data['createdAt'] != null) {
                Timestamp ts = data['createdAt'];
                dateStr = DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
              }

              // ★ 작성자 정보 (이름 + 이메일)
              String email = data['writer'] ?? '익명';
              String name = data['writerName'] ?? ''; // 새로 추가된 필드
              String writerInfo = name.isNotEmpty ? "$name ($email)" : email;

              return ListTile(
                title: Text(
                  "[${data['stationName'] ?? '알 수 없음'}]",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 5),
                    Text(
                      data['content'] ?? '',
                      style: const TextStyle(fontSize: 16, color: Colors.black),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "작성자: $writerInfo  |  시간: $dateStr", // ★ 수정됨
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("메모 삭제"),
                        content: const Text("엑셀에 반영 하셨나요?\n삭제하면 복구할 수 없습니다."),
                        actions: [
                          TextButton(
                            child: const Text("취소"),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                          TextButton(
                            child: const Text(
                              "삭제",
                              style: TextStyle(color: Colors.red),
                            ),
                            onPressed: () {
                              _deleteMemo(docId);
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
