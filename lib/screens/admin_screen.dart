import 'package:flutter/material.dart';
// 아래 파일들이 반드시 있어야 합니다.
import 'user_management_screen.dart';
import 'suggestion_list_screen.dart';
import 'all_memos_screen.dart';
import 'system_config_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

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
