import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 어디서든 불러쓸 수 있는 건의사항 팝업 함수
void showSuggestionDialog(BuildContext context) {
  final TextEditingController contentController = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("💬 건의사항 보내기"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "현재 화면에서 불편한 점을 남겨주세요.\n작성된 내용은 관리자에게 전송됩니다.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: contentController,
            decoration: const InputDecoration(
              hintText: "내용을 입력하세요...",
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("취소"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
          onPressed: () async {
            if (contentController.text.isNotEmpty) {
              final user = FirebaseAuth.instance.currentUser;
              String writerName = "익명";
              String uid = "unknown";

              if (user != null) {
                uid = user.uid;
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .get();
                if (userDoc.exists)
                  writerName = userDoc.data()!['name'] ?? "현장직원";
              }

              // 파이어베이스 저장
              await FirebaseFirestore.instance.collection('suggestions').add({
                'content': contentController.text,
                'writer': writerName,
                'uid': uid,
                'timestamp': FieldValue.serverTimestamp(),
                'isRead': false,
              });

              if (ctx.mounted) {
                // 팝업 닫기 전 체크
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("건의사항이 전송되었습니다.")));
              }
            }
          },
          child: const Text("전송", style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
