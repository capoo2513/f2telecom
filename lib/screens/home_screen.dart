import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart'; // ★ 버전 확인용 패키지
import 'package:url_launcher/url_launcher.dart';

import 'address_book_screen.dart';
import 'schedule_screen.dart';
import 'process_screen.dart';
import 'du_process_screen.dart';
import 'admin_screen.dart';
import 'survey/survey_screen.dart';
// import '../utils/suggestion_helper.dart'; // (없으면 주석 처리)

// 임시 페이지
class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.indigo),
      body: Center(child: Text("$title 화면 준비 중입니다.")),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isDownloading = false;
  bool _isFabExtended = true;
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic> _myScores = {};
  bool _isAdmin = false;
  bool _scoresLoaded = false; // 권한 정보를 받아왔는지 (받기 전엔 메뉴 숨김)

  // ★ [추가됨] 앱 버전을 저장할 변수
  String _appVersion = "";

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
    _recordLoginTime();
    _listenToSystem();
    _getAppVersion(); // ★ [추가됨] 시작할 때 버전 가져오기

    _scrollController.addListener(() {
      if (_scrollController.position.pixels > 10) {
        if (_isFabExtended) setState(() => _isFabExtended = false);
      } else {
        if (!_isFabExtended) setState(() => _isFabExtended = true);
      }
    });
  }

  // ★ [추가됨] 내 앱 버전 가져오는 함수
  Future<void> _getAppVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  Future<void> _checkUserStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        setState(() {
          if (doc.exists) {
            final data = doc.data()!;
            _myScores = data['access_scores'] ?? {};
            _isAdmin = (_myScores['admin'] == 3) || (data['role'] == 'admin');
          }
          _scoresLoaded = true;
        });
      }, onError: (_) {
        if (mounted) setState(() => _scoresLoaded = true);
      });
    }
  }

  Future<void> _recordLoginTime() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastLogin': FieldValue.serverTimestamp(),
        'name': user.displayName ?? '이름없음',
        'email': user.email,
      }, SetOptions(merge: true));
    }
  }

  void _listenToSystem() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String myVersion = packageInfo.version;

    FirebaseFirestore.instance
        .collection('system')
        .doc('config')
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;

      // (1) 공지사항
      if (data['showNotice'] == true && mounted) {
        _showNoticeDialog(
            data['noticeTitle'] ?? '공지사항', data['noticeContent'] ?? '');
      }

      // (2) 앱 버전 체크
      String serverAppVersion = data['android_ver'] ?? '1.0.0'; // 필드명 확인 필요
      String downloadUrl = data['url'] ?? ''; // 필드명 확인 필요

      // 혹시 system/config 문서의 필드명이 다를 수 있으니 안전장치
      if (data.containsKey('latest_app_version')) {
        serverAppVersion = data['latest_app_version'];
      }
      if (data.containsKey('app_download_url')) {
        downloadUrl = data['app_download_url'];
      }

      if (serverAppVersion != myVersion && downloadUrl.isNotEmpty && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("앱 업데이트 알림"),
            content: Text(
                "새로운 버전($serverAppVersion)이 출시되었습니다.\n현재 버전: $myVersion\n\n최신 기능 사용을 위해 업데이트해주세요."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("나중에"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (await canLaunchUrl(Uri.parse(downloadUrl))) {
                    await launchUrl(Uri.parse(downloadUrl),
                        mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text("업데이트 하러가기"),
              ),
            ],
          ),
        );
      }

      // (3) 주소록 데이터 강제 업데이트
      if (data['forceUpdate'] == true && data['csvUrl'] != null) {
        final prefs = await SharedPreferences.getInstance();
        String localVersion = prefs.getString('dataVersion') ?? '0.0';
        String serverVersion = data['dataVersion'] ?? '1.0';
        if (serverVersion != localVersion && mounted) {
          _showUpdateDialog(serverVersion, data['csvUrl'], isIndividual: false);
        }
      }
    });

    // 개별 업데이트 감지
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (data.containsKey('forceUpdateUrl')) {
        String url = data['forceUpdateUrl'];
        if (url.isNotEmpty && mounted) {
          _showUpdateDialog('최신', url, isIndividual: true);
        }
      }
    });
  }

  void _showNoticeDialog(String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.campaign, color: Colors.orange),
          const SizedBox(width: 10),
          Text(title)
        ]),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("확인"))
        ],
      ),
    );
  }

  void _showUpdateDialog(String version, String url,
      {required bool isIndividual}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 업데이트"),
        content: const Text("새로운 주소록 데이터가 있습니다.\n지금 다운로드하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (isIndividual) _clearIndividualUpdate();
            },
            child: const Text("나중에"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadUpdate(url, version, isIndividual);
            },
            child: const Text("다운로드"),
          ),
        ],
      ),
    );
  }

  void _clearIndividualUpdate() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'forceUpdateUrl': FieldValue.delete()});
    }
  }

  Future<void> _downloadUpdate(
      String url, String version, bool isIndividual) async {
    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/addresses.csv');
        await file.writeAsBytes(response.bodyBytes);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('dataVersion', version);
        if (isIndividual) _clearIndividualUpdate();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("업데이트 완료! 앱을 다시 실행해주세요.")));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("오류: $e")));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showSuggestionDialogInternal() async {
    final controller = TextEditingController();
    String userName = "익명";

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name'] ?? "이름없음";
        }
      } catch (e) {
        print("이름 불러오기 실패: $e");
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("건의사항"),
        content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
                hintText: "내용 입력", border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await FirebaseFirestore.instance.collection('suggestions').add({
                  'content': controller.text,
                  'writerEmail': user?.email ?? "익명",
                  'writerName': userName,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text("전송 완료")));
                }
              }
            },
            child: const Text("전송"),
          ),
        ],
      ),
    );
  }

  // 홈 화면에는 권한 점수가 1 이상인 메뉴만 표시
  static const _menuKeys = [
    'address', 'schedule', 'process', 'du_process', 'new_process', 'material'
  ];
  bool _canSee(String key) => ((_myScores[key] ?? 0) as num) > 0;

  void _handleMenuTap(String key, Widget nextPage) {
    int score = _myScores[key] ?? 0;

    if (score == 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("🔒 권한 필요"),
          content: const Text("이 메뉴에 접근할 권한이 없습니다.\n관리자에게 문의하세요."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("확인"))
          ],
        ),
      );
    } else {
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => nextPage));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ★ [수정됨] 제목 옆에 버전 표시 (v1.1.3)
        title: Row(
          mainAxisSize: MainAxisSize.min, // 가운데 정렬 유지
          children: [
            const Text(
              'F2 Telecom',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(width: 8), // 간격
            Text(
              "v$_appVersion", // 버전 텍스트
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminScreen())),
            ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Colors.indigo,
              icon: const Icon(Icons.feedback, color: Colors.white),
              label: _isFabExtended
                  ? const Text("건의사항", style: TextStyle(color: Colors.white))
                  : const SizedBox.shrink(),
              onPressed: _showSuggestionDialogInternal,
            ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text("업무를 선택해주세요",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: !_scoresLoaded
                      ? const Center(child: CircularProgressIndicator())
                      : !_menuKeys.any(_canSee)
                          ? const Center(
                              child: Text("사용 권한이 있는 메뉴가 없습니다.\n관리자에게 문의하세요.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, color: Colors.grey)),
                            )
                          : GridView.count(
                              controller: _scrollController,
                              crossAxisCount: 2,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                              childAspectRatio: 1.1,
                              children: [
                                if (_canSee("address"))
                                  _buildMenuButton("주소록", Icons.import_contacts,
                                      Colors.blue, "address", const AddressBookScreen()),
                                if (_canSee("schedule"))
                                  _buildMenuButton("일정", Icons.calendar_month, Colors.green,
                                      "schedule", const ScheduleScreen()),
                                if (_canSee("process"))
                                  _buildMenuButton("진행사항", Icons.assignment, Colors.orange,
                                      "process", const ProcessScreen()),
                                if (_canSee("du_process"))
                                  _buildMenuButton("DU 진행", Icons.router, Colors.red,
                                      "du_process", const DuProcessScreen()),
                                if (_canSee("new_process"))
                                  _buildMenuButton("실사", Icons.fact_check, Colors.teal,
                                      "new_process", const SurveyStartScreen()),
                                if (_canSee("material"))
                                  _buildMenuButton("자료", Icons.folder_copy, Colors.purple,
                                      "material", const PlaceholderScreen(title: "자료")),
                              ],
                            ),
                ),
              ],
            ),
          ),
          if (_isDownloading)
            Container(
              color: Colors.black54,
              child: const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(
      String title, IconData icon, Color color, String key, Widget nextPage) {
    return InkWell(
      onTap: () => _handleMenuTap(key, nextPage),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
