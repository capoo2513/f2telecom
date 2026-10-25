import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // 삭제 처리
  void _deleteUser(BuildContext context, String docId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("사용자 삭제"),
        content: Text("'$name' 님을 정말 삭제하시겠습니까?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance
                  .collection('users')
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

  // 데이터 업데이트 명령 보내기
  void _sendUpdateCommand(
      BuildContext context, String docId, String name) async {
    final configDoc = await FirebaseFirestore.instance
        .collection('system')
        .doc('config')
        .get();

    if (!configDoc.exists ||
        configDoc.data() == null ||
        configDoc.data()!['csvUrl'] == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("오류: [데이터 갱신] 메뉴에서 먼저 다운로드 URL을 저장해주세요.")),
        );
      }
      return;
    }

    String url = configDoc.data()!['csvUrl'];
    if (url.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("오류: 저장된 URL이 비어있습니다.")),
        );
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'forceUpdateUrl': url,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("'$name' 님에게 최신 데이터 업데이트 명령을 전송했습니다.")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("전송 실패: $e")),
        );
      }
    }
  }

  // ★ [핵심] 권한 설정 다이얼로그 띄우기
  void _showPermissionDialog(BuildContext context, String docId, String name,
      Map<String, dynamic> currentScores) {
    // 점수 관리용 임시 변수 (초기값 세팅)
    // Map은 참조형이라 복사해서 써야 함
    Map<String, int> tempScores = {
      'schedule': currentScores['schedule'] ?? 0,
      'address': currentScores['address'] ?? 0,
      'process': currentScores['process'] ?? 0,
      'du_process': currentScores['du_process'] ?? 0,
      'new_process': currentScores['new_process'] ?? 0,
      'material': currentScores['material'] ?? 0,
      // 관리자 권한은 별도로 체크 (0 or 3)
      'admin': currentScores['admin'] ?? 0,
    };

    // 메뉴 한글 이름 매핑
    final menuNames = {
      'schedule': '📅 일정 관리',
      'address': '📒 주소록',
      'process': '📝 진행 내역',
      'du_process': '🏗️ DU 공정',
      'new_process': '📷 실사',
      'material': '📂 자료 (New)',
      'admin': '👮 관리자 메뉴'
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("$name 권한 설정"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: menuNames.entries.map((entry) {
                    String key = entry.key;
                    String title = entry.value;
                    int score = tempScores[key] ?? 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            // 점수 선택 라디오 버튼 (0~3점)
                            // 관리자 메뉴는 0(없음) 또는 3(있음)만 선택 가능하게 하면 깔끔함
                            key == 'admin'
                                ? Row(
                                    children: [
                                      _buildRadio(
                                          0,
                                          "없음",
                                          score,
                                          (val) => setState(
                                              () => tempScores[key] = val)),
                                      _buildRadio(
                                          3,
                                          "관리자",
                                          score,
                                          (val) => setState(
                                              () => tempScores[key] = val)),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildRadio(
                                          0,
                                          "잠금",
                                          score,
                                          (val) => setState(
                                              () => tempScores[key] = val)),
                                      _buildRadio(
                                          1,
                                          "제한",
                                          score,
                                          (val) => setState(
                                              () => tempScores[key] = val)),
                                      _buildRadio(
                                          2,
                                          "조회",
                                          score,
                                          (val) => setState(
                                              () => tempScores[key] = val)),
                                      _buildRadio(
                                          3,
                                          "수정",
                                          score,
                                          (val) => setState(
                                              () => tempScores[key] = val)),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("취소")),
                ElevatedButton(
                  onPressed: () async {
                    // 저장 로직
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(docId)
                        .update({
                      'access_scores': tempScores,
                      'isApproved': true, // 권한 설정하면 자동 승인
                      // 기존 role 필드도 호환성을 위해 업데이트 (관리자 권한 있으면 admin)
                      'role': (tempScores['admin'] == 3) ? 'admin' : 'user',
                    });
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: const Text("저장 및 승인"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 라디오 버튼 위젯 도우미
  Widget _buildRadio(
      int value, String label, int groupValue, Function(int) onChanged) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<int>(
            value: value,
            groupValue: groupValue,
            onChanged: (val) => onChanged(val!),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("사용자 관리"),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) return const Center(child: Text("가입한 사용자가 없습니다."));

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;

              String name = data['name'] ?? '이름없음';
              String email = data['email'] ?? '-';
              bool isApproved = data['isApproved'] ?? false;

              // 현재 점수 가져오기 (없으면 빈 맵)
              Map<String, dynamic> currentScores = data['access_scores'] ?? {};

              Timestamp? lastLogin = data['lastLogin'];
              String lastLoginStr = lastLogin != null
                  ? DateFormat('MM/dd HH:mm').format(lastLogin.toDate())
                  : "-";

              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  // ★ 카드를 누르면 권한 설정 팝업 뜸
                  onTap: () => _showPermissionDialog(
                      context, docId, name, currentScores),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isApproved ? Colors.indigo : Colors.grey,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email),
                        Text("최근접속: $lastLoginStr",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        if (!isApproved)
                          const Text("⚠️ 승인 대기중 (탭하여 승인)",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 데이터 전송 버튼
                        if (isApproved)
                          IconButton(
                            icon: const Icon(Icons.send_to_mobile,
                                color: Colors.blue),
                            tooltip: "최신 데이터 개별 전송",
                            onPressed: () =>
                                _sendUpdateCommand(context, docId, name),
                          ),
                        // 삭제 버튼
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: "사용자 삭제",
                          onPressed: () => _deleteUser(context, docId, name),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
