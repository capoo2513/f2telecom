import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';
import '../services/phone_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _idController = TextEditingController(); // 로그인: 전화번호 (또는 이메일)
  final _emailController = TextEditingController(); // 회원가입: 이메일
  final _phoneController = TextEditingController(); // 회원가입: 전화번호
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController(); // 이름 입력용

  bool _isSignup = false; // true면 회원가입 모드
  bool _isLoading = false;
  bool _canBiometric = false; // 3일 이내 로그인 기록이 있으면 [지문으로 로그인] 버튼 표시
  bool _useEmail = false; // 전화번호 등록 전 직원용: 이메일로 로그인

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailable();
  }

  @override
  void dispose() {
    _idController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailable() async {
    final ok = await PhoneAuthService.isSessionValid();
    if (mounted) setState(() => _canBiometric = ok);
  }

  /// [지문으로 로그인] (3일 이내)
  Future<void> _biometricLogin() async {
    if (!await PhoneAuthService.isSessionValid()) {
      if (mounted) setState(() => _canBiometric = false);
      return;
    }
    final ok = await PhoneAuthService.unlockWithBiometrics();
    if (!ok || !mounted) return;
    await PhoneAuthService.markLoggedIn(); // 3일 다시 시작
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  /// [비밀번호 찾기] 전화번호 → 등록된 이메일로 재설정 메일
  void _showPasswordReset() {
    final ctrl = TextEditingController(text: _useEmail ? '' : _idController.text);
    bool sending = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("비밀번호 찾기"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("가입한 전화번호를 입력하면\n등록된 이메일로 비밀번호 재설정 메일을 보냅니다.",
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: "전화번호",
                    hintText: "010-1234-5678",
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ElevatedButton(
              onPressed: sending
                  ? null
                  : () async {
                      setD(() => sending = true);
                      final msg = await PhoneAuthService.sendPasswordReset(ctrl.text);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("비밀번호 찾기"),
                          content: Text(msg),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text("확인"))
                          ],
                        ),
                      );
                    },
              child: sending
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("메일 보내기"),
            ),
          ],
        ),
      ),
    );
  }

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
        final phone = PhoneAuthService.cleanPhone(_phoneController.text);
        if (phone.length < 10) {
          throw FirebaseAuthException(
              code: 'missing-phone', message: '전화번호를 입력해주세요.');
        }
        if (await PhoneAuthService.isPhoneTaken(phone)) {
          throw FirebaseAuthException(
              code: 'phone-already-in-use', message: '이미 등록된 전화번호입니다.');
        }

        // 1. Firebase Auth에 계정 생성
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // 계정이 만들어진 직후, Auth 프로필에 이름을 넣어줍니다.
        if (userCredential.user != null) {
          await userCredential.user!
              .updateDisplayName(_nameController.text.trim());
          await userCredential.user!.reload(); // (선택사항) 정보 갱신
        }

        // 2. Firestore DB에 사용자 정보 저장
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'email': _emailController.text.trim(),
          'name': _nameController.text.trim(),
          'phone': phone,
          'role': 'user',
          'level': 1,
          'isApproved': false,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });

        // 3. 전화번호 로그인용 색인 저장
        final err = await PhoneAuthService.setPhone(
          uid: userCredential.user!.uid,
          email: _emailController.text.trim(),
          newPhone: phone,
        );
        if (err != null) debugPrint('전화번호 색인 저장 실패: $err');

        // 승인 전이므로 로그아웃 상태로 돌려놓기
        await _auth.signOut();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("가입 신청 완료! 관리자 승인 대기중.")));
          // 가입 성공 후 로그인 화면으로 전환 (전화번호 미리 채움)
          setState(() {
            _isSignup = false;
            _idController.text = PhoneAuthService.formatPhone(phone);
            _passwordController.clear();
          });
        }
      } else {
        // ===========================
        // [로그인 로직] 전화번호(또는 이메일) + 비밀번호
        // ===========================
        final userCredential = await PhoneAuthService.signIn(
          _idController.text,
          _passwordController.text.trim(),
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

          // 3일 생체인식 자동 로그인용 기록
          await PhoneAuthService.markLoggedIn();
          // 이메일 변경 인증을 마쳤으면 전화번호 로그인 정보도 새 이메일로 맞춤
          await PhoneAuthService.syncEmailAfterLogin();

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
          case 'wrong-password':
            message = _useEmail
                ? "이메일 또는 비밀번호가 잘못되었습니다."
                : "전화번호 또는 비밀번호가 잘못되었습니다.";
            break;
          case 'user-disabled':
            message = "정지된 계정입니다. 관리자에게 문의하세요.";
            break;
          case 'phone-not-found':
            message = "등록되지 않은 전화번호입니다.\n관리자에게 전화번호 등록을 요청하세요.";
            break;

          // --- 회원가입 관련 에러 ---
          case 'email-already-in-use':
            message = "이미 가입된 이메일 주소입니다. 로그인을 시도해주세요.";
            break;
          case 'phone-already-in-use':
            message = "이미 등록된 전화번호입니다. 로그인을 시도해주세요.";
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
          case 'missing-phone':
            message = "전화번호를 입력해주세요.";
            break;

          // --- 그 외 알 수 없는 에러 코드 ---
          default:
            message = "오류 발생: [${e.code}] 관리자에게 문의하세요.";
            break;
        }
      } else if (e is FirebaseException && e.code == 'permission-denied') {
        message = "전화번호 조회 권한이 없습니다.\n관리자에게 문의하세요. (Firestore 규칙 확인 필요)";
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

                  if (!_isSignup) ...[
                    // 로그인: 전화번호 (전화번호 등록 전이면 이메일)
                    TextField(
                        key: ValueKey(_useEmail),
                        controller: _idController,
                        keyboardType: _useEmail
                            ? TextInputType.emailAddress
                            : TextInputType.phone,
                        decoration: InputDecoration(
                            labelText: _useEmail ? "이메일" : "전화번호",
                            hintText: _useEmail ? null : "010-1234-5678",
                            prefixIcon: Icon(_useEmail
                                ? Icons.email_outlined
                                : Icons.phone_android),
                            border: const OutlineInputBorder())),
                    const SizedBox(height: 10),
                  ] else ...[
                    // 회원가입: 이메일 + 전화번호
                    TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: "이메일", border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))
                        ],
                        decoration: const InputDecoration(
                            labelText: "전화번호 (로그인할 때 사용)",
                            hintText: "010-1234-5678",
                            border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                  ],

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

                  // 3일 이내 로그인 기록이 있으면 지문 로그인 버튼
                  if (!_isSignup && _canBiometric) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _biometricLogin,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text("지문으로 로그인"),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48)),
                    ),
                  ],

                  // 비밀번호 찾기
                  if (!_isSignup)
                    TextButton(
                      onPressed: _showPasswordReset,
                      child: const Text("비밀번호를 잊으셨나요? 비밀번호 찾기"),
                    ),

                  // 전화번호가 아직 등록되지 않은 직원용
                  if (!_isSignup)
                    TextButton(
                      onPressed: () => setState(() {
                        _useEmail = !_useEmail;
                        _idController.clear();
                      }),
                      child: Text(_useEmail ? "전화번호로 로그인" : "이메일로 로그인",
                          style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ),

                  // 전환 버튼
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isSignup = !_isSignup;
                        // 에러 방지를 위해 입력창 초기화
                        _idController.clear();
                        _emailController.clear();
                        _phoneController.clear();
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
