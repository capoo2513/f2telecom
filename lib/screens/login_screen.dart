import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController(); // 이름 입력용

  bool _isSignup = false; // true면 회원가입 모드
  bool _isLoading = false;

  void _submit() async {
    // 키보드 내리기
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);
    try {
      if (_isSignup) {
        // ===========================
        // [회원가입 로직]
        // ===========================
        if (_nameController.text.trim().isEmpty) {
          throw FirebaseAuthException(
              code: 'missing-name', message: '이름을 입력해주세요.');
        }

        // 1. Firebase Auth에 계정 생성
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // ★ [여기가 핵심 수정 부분입니다] ★
        // 계정이 만들어진 직후, Auth 프로필에 이름을 강제로 심어줍니다.
        if (userCredential.user != null) {
          await userCredential.user!
              .updateDisplayName(_nameController.text.trim());
          await userCredential.user!.reload(); // (선택사항) 정보 갱신
        }
        // ------------------------------------------

        // 2. Firestore DB에 사용자 정보 저장
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'email': _emailController.text.trim(),
          'name': _nameController.text.trim(),
          'role': 'user',
          'level': 1,
          'isApproved': false,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("가입 신청 완료! 관리자 승인 대기중.")));
          // 가입 성공 후 로그인 화면으로 전환
          setState(() => _isSignup = false);
        }
      } else {
        // ===========================
        // [로그인 로직]
        // ===========================
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // 3. 승인 여부 확인
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        if (doc.exists && (doc.data()!['isApproved'] == true)) {
          // 승인된 사용자 -> 접속시간 갱신 & 홈으로 이동
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({
            'lastLogin': FieldValue.serverTimestamp(),
          });

          // 자동 로그인을 위한 로컬 저장
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'last_login_date', DateTime.now().toIso8601String());
          await prefs.setBool('is_logged_in', true);

          if (mounted) {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          }
        } else {
          // 승인 안됨 -> 로그아웃 처리
          await _auth.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text("관리자 승인이 필요합니다.")));
          }
        }
      }
    } catch (e) {
      // 1. 기본 에러 메시지 설정
      String message = "알 수 없는 오류가 발생했습니다. 잠시 후 다시 시도해주세요.";

      // 2. Firebase 인증 에러일 경우, 에러 코드(e.code)를 확인해 한글로 변환
      if (e is FirebaseAuthException) {
        switch (e.code) {
          // --- 로그인 관련 에러 ---
          case 'user-not-found':
          case 'invalid-email':
          case 'invalid-credential': // 최신 파이어베이스에서 자주 뜸
            message = "이메일이 존재하지 않거나 아이디/비밀번호가 틀렸습니다.";
            break;
          case 'wrong-password':
            message = "비밀번호가 틀렸습니다.";
            break;
          case 'user-disabled':
            message = "정지된 계정입니다. 관리자에게 문의하세요.";
            break;

          // --- 회원가입 관련 에러 ---
          case 'email-already-in-use':
            message = "이미 가입된 이메일 주소입니다. 로그인을 시도해주세요.";
            break;
          case 'weak-password':
            message = "비밀번호 보안이 취약합니다. 6자리 이상 영문/숫자를 섞어주세요.";
            break;
          case 'operation-not-allowed':
            message = "이메일/비밀번호 가입이 비활성화되어 있습니다. 관리자에게 문의하세요.";
            break;

          // --- 시스템/네트워크 관련 에러 ---
          case 'network-request-failed':
            message = "네트워크 연결이 불안정합니다. 와이파이나 데이터를 확인해주세요.";
            break;
          case 'too-many-requests':
            message = "접속 시도가 너무 많아 잠시 차단되었습니다. 잠시 후 다시 시도해주세요.";
            break;

          // --- 우리가 직접 만든 커스텀 에러 ---
          case 'missing-name':
            message = "이름을 입력해주세요.";
            break;

          // --- 그 외 알 수 없는 에러 코드 ---
          default:
            message = "오류 발생: [${e.code}] 관리자에게 문의하세요.";
            break;
        }
      }
      // Firebase 에러가 아닌 일반 프로그래밍 에러일 때
      else {
        message = "시스템 오류가 발생했습니다: $e";
      }

      // 3. 화면에 붉은색 스낵바(알림) 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // 로딩 뱅글이 멈추기
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo,
      body: Center(
        child: SingleChildScrollView(
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 50, color: Colors.indigo),
                  const SizedBox(height: 20),

                  // 제목
                  Text(
                    _isSignup ? "회원가입" : "F2 Telecom 로그인",
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: "이메일", border: OutlineInputBorder())),
                  const SizedBox(height: 10),

                  TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: "비밀번호", border: OutlineInputBorder())),
                  const SizedBox(height: 10),

                  // ★ 회원가입일 때만 이름 입력창 표시
                  if (_isSignup)
                    TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                            labelText: "이름 (실명)",
                            border: OutlineInputBorder())),

                  const SizedBox(height: 20),

                  // 버튼 (로그인 / 가입신청)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isSignup ? "가입신청" : "로그인"),
                  ),

                  // 전환 버튼
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isSignup = !_isSignup;
                        // 에러 방지를 위해 입력창 초기화
                        _emailController.clear();
                        _passwordController.clear();
                        _nameController.clear();
                      });
                    },
                    child: Text(_isSignup ? "이미 계정이 있으신가요? 로그인" : "새 계정 만들기"),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
