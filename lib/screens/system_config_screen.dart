import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SystemConfigScreen extends StatefulWidget {
  const SystemConfigScreen({super.key});

  @override
  State<SystemConfigScreen> createState() => _SystemConfigScreenState();
}

class _SystemConfigScreenState extends State<SystemConfigScreen> {
  // 컨트롤러
  final _noticeTitleController = TextEditingController();
  final _noticeContentController = TextEditingController();
  final _versionController = TextEditingController(); // 데이터 버전
  final _urlController = TextEditingController(); // CSV 파일 주소

  // 상태 변수
  bool _showNotice = false; // 공지사항 보이기/숨기기
  bool _forceUpdate = false; // 전체 업데이트 알림 띄우기 여부
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _noticeTitleController.dispose();
    _noticeContentController.dispose();
    _versionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // 1. 현재 설정 불러오기
  void _loadCurrentConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system')
          .doc('config')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _showNotice = data['showNotice'] ?? false;
          _forceUpdate = data['forceUpdate'] ?? false; // 업데이트 알림 여부
          _noticeTitleController.text = data['noticeTitle'] ?? '';
          _noticeContentController.text = data['noticeContent'] ?? '';
          _versionController.text = data['dataVersion'] ?? '1.0';
          _urlController.text = data['csvUrl'] ?? '';
        });
      }
    } catch (e) {
      // 에러 무시 혹은 로그
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. 설정 저장하기
  void _saveConfig() async {
    if (_versionController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("데이터 버전을 입력해주세요.")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('system').doc('config').set({
        // [공지사항 설정]
        'showNotice': _showNotice,
        'noticeTitle': _noticeTitleController.text,
        'noticeContent': _noticeContentController.text,

        // [데이터 업데이트 설정]
        'forceUpdate': _forceUpdate, // 전체 알림 여부
        'dataVersion': _versionController.text,
        'csvUrl': _urlController.text,

        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("설정이 저장되었습니다.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("저장 실패")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("시스템 관리"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // [섹션 1] 공지사항 (데이터 버전과 무관하게 동작)
                  const Text("📢 공지사항 설정",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text("앱 실행 시 공지 띄우기"),
                            subtitle: Text(
                                _showNotice ? "켜짐 (모든 사용자가 볼 수 있습니다)" : "꺼짐"),
                            value: _showNotice,
                            activeColor: Colors.indigo,
                            onChanged: (val) =>
                                setState(() => _showNotice = val),
                          ),
                          const Divider(),
                          TextField(
                            controller: _noticeTitleController,
                            decoration: const InputDecoration(
                              labelText: "공지 제목",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.title),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _noticeContentController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: "공지 내용",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.article),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // [섹션 2] 데이터 버전 관리 (전체/개별 선택 가능)
                  const Text("🔄 주소록 데이터 설정",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          const Text(
                            "여기서 저장한 '다운로드 URL'은 [사용자 관리] 메뉴에서\n개별 전송할 때 자동으로 불러와집니다.",
                            style: TextStyle(fontSize: 13, color: Colors.blue),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              labelText: "CSV 파일 다운로드 URL (필수)",
                              hintText: "https://firebasestorage...",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _versionController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "데이터 버전 (예: 1.2)",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.tag),
                            ),
                          ),
                          const Divider(height: 30),
                          // ★ 전체 알림 스위치 추가
                          SwitchListTile(
                            title: const Text("전체 사용자에게 업데이트 알림"),
                            subtitle: Text(_forceUpdate
                                ? "켜짐 (모든 사용자가 업데이트 팝업을 받습니다)"
                                : "꺼짐 (개별 전송만 가능)"),
                            value: _forceUpdate,
                            activeColor: Colors.red, // 주의 색상
                            onChanged: (val) =>
                                setState(() => _forceUpdate = val),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // 저장 버튼
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saveConfig,
                      icon: const Icon(Icons.save),
                      label:
                          const Text("설정 저장", style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
