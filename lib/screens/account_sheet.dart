import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/phone_auth_service.dart';
import 'login_screen.dart';

/// 홈 화면 오른쪽 위 [내 정보] → 비밀번호 변경 / 이메일 변경 / 로그아웃
Future<void> showAccountSheet(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  Map<String, dynamic> data = {};
  try {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    data = doc.data() ?? {};
  } catch (_) {}
  if (!context.mounted) return;

  final name = (data['name'] ?? user.displayName ?? '').toString();
  final phone = (data['phone'] ?? '').toString();
  final pending = (data['pendingEmail'] ?? '').toString();

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.indigo,
                child: Icon(Icons.person, color: Colors.white)),
            title: Text(name.isEmpty ? '내 정보' : name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text([
              if (phone.isNotEmpty) '전화: ${PhoneAuthService.formatPhone(phone)}',
              '이메일: ${user.email ?? '-'}',
              if (pending.isNotEmpty) '변경 대기: $pending (메일 인증 필요)',
            ].join('\n')),
            isThreeLine: true,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('비밀번호 변경'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _showChangePassword(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('이메일 주소 변경'),
            subtitle: const Text('비밀번호 찾기 메일을 받을 주소'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _showChangeEmail(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('로그아웃'),
                  content: const Text('로그아웃하면 다음에 전화번호와 비밀번호를 다시 입력해야 합니다.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('로그아웃', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (ok != true) return;
              await PhoneAuthService.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showChangePassword(BuildContext context) {
  final cur = TextEditingController();
  final next = TextEditingController();
  final next2 = TextEditingController();
  String? error;
  bool busy = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('비밀번호 변경'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: cur,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '현재 비밀번호', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '새 비밀번호 (6자리 이상)', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: next2,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '새 비밀번호 확인', border: OutlineInputBorder())),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    if (next.text != next2.text) {
                      setD(() => error = '새 비밀번호가 서로 다릅니다.');
                      return;
                    }
                    setD(() {
                      busy = true;
                      error = null;
                    });
                    final err = await PhoneAuthService.changePassword(cur.text, next.text);
                    if (!ctx.mounted) return;
                    if (err != null) {
                      setD(() {
                        busy = false;
                        error = err;
                      });
                      return;
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('비밀번호가 변경되었습니다.')));
                  },
            child: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('변경'),
          ),
        ],
      ),
    ),
  );
}

void _showChangeEmail(BuildContext context) {
  final cur = TextEditingController();
  final email = TextEditingController();
  String? error;
  bool busy = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('이메일 주소 변경'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('새 주소로 인증 메일이 갑니다.\n메일의 링크를 눌러야 변경이 완료됩니다.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: '새 이메일 주소', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: cur,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '현재 비밀번호 (본인 확인)', border: OutlineInputBorder())),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    setD(() {
                      busy = true;
                      error = null;
                    });
                    final err = await PhoneAuthService.requestEmailChange(cur.text, email.text);
                    if (!ctx.mounted) return;
                    if (err != null) {
                      setD(() {
                        busy = false;
                        error = err;
                      });
                      return;
                    }
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('인증 메일을 보냈습니다'),
                        content: Text('${email.text.trim()} 메일함(스팸함 포함)에서\n'
                            '인증 링크를 눌러주세요.\n\n'
                            '인증 전까지는 기존 이메일이 그대로 유지되고,\n'
                            '전화번호 로그인은 계속 됩니다.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))
                        ],
                      ),
                    );
                  },
            child: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('인증 메일 보내기'),
          ),
        ],
      ),
    ),
  );
}
