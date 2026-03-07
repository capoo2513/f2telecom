import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SuggestionListScreen extends StatelessWidget {
  const SuggestionListScreen({super.key});

  // [기능 1] 읽음 처리 함수
  void _markAsRead(String docId) {
    FirebaseFirestore.instance.collection('suggestions').doc(docId).update({
      'isRead': true,
    });
  }

  // [기능 2] 삭제 함수
  void _deleteSuggestion(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("건의사항 삭제"),
        content: const Text("이 건의사항을 삭제하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          TextButton(
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
            onPressed: () {
              FirebaseFirestore.instance
                  .collection('suggestions')
                  .doc(docId)
                  .delete();
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  // [기능 3] 내용 상세 보기 팝업 (수정됨: 이름 표시)
  void _showDetail(
      BuildContext context, Map<String, dynamic> data, String docId) {
    // 1. 읽지 않은 상태라면 '읽음'으로 변경
    bool isRead = data['isRead'] ?? false;
    if (isRead == false) {
      _markAsRead(docId);
    }

    // 이름과 이메일 가져오기
    String email = data['writerEmail'] ?? "익명";
    String name = data['writerName'] ?? ""; // 이름이 없을 수도 있음
    String senderInfo = name.isNotEmpty ? "$name ($email)" : email;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.feedback, color: Colors.indigo),
            const SizedBox(width: 10),
            Expanded(
              // ★ 수정됨: 이름(이메일) 형태로 표시
              child: Text(
                senderInfo,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("내용:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 5),
              Text(data['content'] ?? "", style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "작성일: ${_formatDate(data['createdAt'])}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("확인"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // 팝업 닫고
              _deleteSuggestion(context, docId); // 삭제 팝업 호출
            },
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 날짜 포맷 함수
  String _formatDate(Timestamp? ts) {
    if (ts == null) return "-";
    return DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("건의사항함"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('suggestions')
            .orderBy('createdAt', descending: true) // 최신순 정렬
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("오류 발생"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 50, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("도착한 건의사항이 없습니다.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;

              // 읽음 상태 체크
              final bool isRead = data['isRead'] ?? false;

              // 정보 가져오기
              String email = data['writerEmail'] ?? "익명";
              String name = data['writerName'] ?? "";
              String senderInfo = name.isNotEmpty ? "$name ($email)" : email;

              return ListTile(
                // 읽지 않았으면 배경색을 연한 색으로 표시
                tileColor: isRead ? Colors.white : Colors.indigo.shade50,
                leading: CircleAvatar(
                  backgroundColor:
                      isRead ? Colors.grey.shade300 : Colors.indigo,
                  child: Icon(
                    isRead ? Icons.mark_email_read : Icons.mark_email_unread,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  data['content'] ?? "",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isRead
                        ? FontWeight.normal
                        : FontWeight.bold, // 안 읽었으면 굵게
                  ),
                ),
                // ★ 수정됨: 이름(이메일) 형태로 표시
                subtitle: Text(
                  "$senderInfo  |  ${_formatDate(data['createdAt'])}",
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: isRead
                    ? null
                    : const Icon(Icons.circle,
                        color: Colors.red, size: 10), // 안 읽음 빨간 점
                onTap: () => _showDetail(context, data, docId),
              );
            },
          );
        },
      ),
    );
  }
}
