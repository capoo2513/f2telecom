import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// 아래 파일들이 반드시 있어야 합니다.
import 'user_management_screen.dart';
import 'suggestion_list_screen.dart';
import 'all_memos_screen.dart';
import 'system_config_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  StreamSubscription? _sub;
  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    // 관리자 메뉴(사용자 관리 등)를 열어 둔 동안에도 내 권한을 계속 확인:
    // 관리자 권한이 빠지면 관리자 화면을 모두 닫고 홈으로
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _kickOut());
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      final scores = (data?['access_scores'] as Map?) ?? {};
      final isAdmin = scores['admin'] == 3 || data?['role'] == 'admin';
      if (!isAdmin) _kickOut();
    });
  }

  void _kickOut() {
    if (_kicked || !mounted) return;
    _kicked = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    messenger.showSnackBar(
        const SnackBar(content: Text('관리자 권한이 없어 관리자 메뉴를 닫았습니다.')));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ★ 제목을 변경했습니다. 앱에서 이 제목이 보여야 정상입니다!
        title: const Text("관리자 메뉴"),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          children: [
            _menuCard(context, Icons.people, "사용자 관리", "승인/삭제",
                const UserManagementScreen()),
            _menuCard(context, Icons.feedback, "건의사항", "피드백 확인",
                const SuggestionListScreen()),
            _menuCard(
                context, Icons.note, "메모 관리", "현장 메모", const AllMemosScreen()),
            _menuCard(context, Icons.update, "데이터 갱신", "공지 설정",
                const SystemConfigScreen()),
          ],
        ),
      ),
    );
  }

  Widget _menuCard(BuildContext context, IconData icon, String title,
      String sub, Widget page) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.indigo),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
