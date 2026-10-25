import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../utils/version_util.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 애니메이션 설정 (1.5초)
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    _controller.forward();

    // 시작하자마자 업데이트 체크 실행
    _checkAppVersion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 버전 체크 함수
  Future<void> _checkAppVersion() async {
    // 로고 애니메이션 감상을 위해 잠시 대기 (1.5초)
    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      // 1. 내 앱 버전 확인
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      // 2. 파이어베이스 버전 확인 (system -> config)
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('system')
          .doc('config')
          .get();

      if (doc.exists) {
        Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;

        if (data != null && data.containsKey('android_ver')) {
          String serverVersion = data['android_ver'];
          String downloadUrl = data['url'] ?? "";

          // 3. 버전 비교 (서버 버전이 더 높을 때만 업데이트 팝업)
          if (isNewerVersion(serverVersion, currentVersion)) {
            if (!mounted) return;
            _showUpdateDialog(downloadUrl);
            return; // 업데이트 창이 뜨면 로그인 화면으로 넘어가지 않음
          }
        }
      }
    } catch (e) {
      // 인터넷 연결 문제 등으로 체크 실패 시, 조용히 로그인 화면으로 이동
      print("버전 체크 실패: $e");
    }

    // 업데이트가 없거나 에러 발생 시 로그인 체크 진행
    _checkLogin();
  }

  // 업데이트 알림 팝업
  void _showUpdateDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false, // 바깥 눌러도 안 닫힘
      builder: (ctx) => AlertDialog(
        title: const Text("업데이트 알림"),
        content: const Text("새로운 버전이 출시되었습니다.\n원활한 사용을 위해 업데이트해주세요."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkLogin(); // '나중에' 누르면 앱 진입
            },
            child: const Text("나중에"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (url.isNotEmpty) {
                final Uri uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: const Text("업데이트 하기"),
          ),
        ],
      ),
    );
  }

  // 로그인 상태 체크 및 화면 이동
  void _checkLogin() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final String? lastLoginStr = prefs.getString('last_login_date');

    if (isLoggedIn && lastLoginStr != null) {
      DateTime lastLogin = DateTime.parse(lastLoginStr);
      DateTime now = DateTime.now();

      // 마지막 로그인으로부터 10일 지났으면 재로그인 유도
      if (now.difference(lastLogin).inDays >= 10) {
        await prefs.setBool('is_logged_in', false);
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      } else {
        // 로그인 유지 -> 메인 화면으로
        await prefs.setString('last_login_date', now.toIso8601String());
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        }
      }
    } else {
      // 미로그인 상태 -> 로그인 화면으로
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _animation,
          child: SizedBox(
            width: 200,
            height: 200,
            child: Image.asset(
              'assets/images/icon.png',
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.cell_tower,
                    size: 150, color: Colors.indigo);
              },
            ),
          ),
        ),
      ),
    );
  }
}
