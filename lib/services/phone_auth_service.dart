import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 전화번호 로그인 + 3일(72시간) 생체인식 자동 로그인
///
/// [로그인 구조] (자재앱과 같은 방식)
///  - Firebase 계정은 기존처럼 "이메일 + 비밀번호"
///  - 전화번호 → 이메일 찾기 : Firestore `phone_index/{전화번호}` 문서 { email, uid }
///    (로그인 전에도 읽을 수 있어야 하므로 users 와 분리. Firestore 규칙에서 읽기 허용 필요)
///  - users/{uid} 문서에도 phone 필드 저장
///
/// [3일 규칙] 마지막 로그인(비밀번호 또는 생체인식 성공) 후 72시간 이내면 생체인식으로 바로 입장,
///           72시간이 지나면 전화번호 + 비밀번호를 다시 입력
class PhoneAuthService {
  static const _kLoggedIn = 'is_logged_in';
  static const _kLastLogin = 'last_login_date';
  static const int sessionHours = 72;

  static final _db = FirebaseFirestore.instance;
  static final _localAuth = LocalAuthentication();

  /// 숫자만 남기기 (010-1234-5678 → 01012345678)
  static String cleanPhone(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

  /// 보기 좋게 (01012345678 → 010-1234-5678)
  static String formatPhone(String phone) {
    final p = cleanPhone(phone);
    if (p.length == 11) return '${p.substring(0, 3)}-${p.substring(3, 7)}-${p.substring(7)}';
    if (p.length == 10) return '${p.substring(0, 3)}-${p.substring(3, 6)}-${p.substring(6)}';
    return p;
  }

  /// 로그인 입력값으로 Firebase 이메일 찾기
  ///  - '@' 가 있으면 이메일로 그대로 사용 (전화번호 등록 전 직원용 예비 로그인)
  ///  - 전화번호면 phone_index 에서 이메일 조회, 없으면 null
  static Future<String?> resolveEmail(String input) async {
    final v = input.trim();
    if (v.contains('@')) return v;
    final p = cleanPhone(v);
    if (p.isEmpty) return null;
    final doc = await _db.collection('phone_index').doc(p).get();
    final email = doc.data()?['email'];
    return (email is String && email.isNotEmpty) ? email : null;
  }

  /// 이 전화번호가 이미 다른 계정에 등록되어 있는지 (uid 가 다르면 true)
  static Future<bool> isPhoneTaken(String phone, {String? exceptUid}) async {
    final p = cleanPhone(phone);
    final doc = await _db.collection('phone_index').doc(p).get();
    if (!doc.exists) return false;
    return doc.data()?['uid'] != exceptUid;
  }

  /// 전화번호 등록/변경 (관리자 화면, 회원가입에서 사용)
  /// users/{uid}.phone 과 phone_index 를 함께 갱신. 실패 시 오류 메시지, 성공 시 null
  static Future<String?> setPhone({
    required String uid,
    required String email,
    required String newPhone,
    String? oldPhone,
  }) async {
    final p = cleanPhone(newPhone);
    if (p.length < 10) return '전화번호를 정확히 입력해주세요.';
    if (email.isEmpty) return '이 사용자에게 저장된 이메일이 없어 전화번호 로그인을 만들 수 없습니다.';
    try {
      if (await isPhoneTaken(p, exceptUid: uid)) {
        return '이미 다른 사용자에게 등록된 전화번호입니다.';
      }
      final batch = _db.batch();
      batch.set(_db.collection('users').doc(uid), {'phone': p}, SetOptions(merge: true));
      batch.set(_db.collection('phone_index').doc(p), {
        'email': email,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final old = cleanPhone(oldPhone ?? '');
      if (old.isNotEmpty && old != p) {
        batch.delete(_db.collection('phone_index').doc(old));
      }
      await batch.commit();
      return null;
    } catch (e) {
      return '전화번호 저장 실패: $e';
    }
  }

  /// 전화번호(또는 이메일) + 비밀번호로 로그인
  /// 이메일 변경 인증 대기 중(pendingEmail)이면 새 이메일로도 시도
  static Future<UserCredential> signIn(String input, String password) async {
    final auth = FirebaseAuth.instance;
    final v = input.trim();
    final candidates = <String>[];
    if (v.contains('@')) {
      candidates.add(v);
    } else {
      final p = cleanPhone(v);
      if (p.isEmpty) {
        throw FirebaseAuthException(code: 'phone-not-found');
      }
      final doc = await _db.collection('phone_index').doc(p).get();
      final data = doc.data() ?? {};
      for (final k in ['email', 'pendingEmail']) {
        final e = data[k];
        if (e is String && e.isNotEmpty && !candidates.contains(e)) candidates.add(e);
      }
      if (candidates.isEmpty) {
        throw FirebaseAuthException(code: 'phone-not-found');
      }
    }
    FirebaseAuthException? lastError;
    for (final email in candidates) {
      try {
        return await auth.signInWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (e) {
        lastError = e;
        // 비밀번호 틀림/계정 없음이면 다음 후보(새 이메일)로 시도, 그 외 오류는 바로 중단
        if (!['invalid-credential', 'wrong-password', 'user-not-found', 'invalid-email']
            .contains(e.code)) {
          rethrow;
        }
      }
    }
    throw lastError ?? FirebaseAuthException(code: 'invalid-credential');
  }

  /// 로그인 성공 후: 실제 로그인 이메일과 저장된 이메일이 다르면(이메일 변경 인증 완료) 맞춰줌
  static Future<void> syncEmailAfterLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    try {
      final udoc = await _db.collection('users').doc(user.uid).get();
      final data = udoc.data() ?? {};
      final phone = cleanPhone((data['phone'] ?? '').toString());
      final updates = <String, dynamic>{};
      if (data['email'] != user.email) updates['email'] = user.email;
      if (data.containsKey('pendingEmail')) updates['pendingEmail'] = FieldValue.delete();
      if (updates.isNotEmpty) {
        await _db.collection('users').doc(user.uid).set(updates, SetOptions(merge: true));
      }
      if (phone.isNotEmpty) {
        await _db.collection('phone_index').doc(phone).set({
          'email': user.email,
          'uid': user.uid,
          'pendingEmail': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      // 동기화 실패해도 로그인은 계속
    }
  }

  /// 이메일 일부 가리기 (abcd1234@gmail.com → ab******@gmail.com)
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 2) return email;
    return email.substring(0, 2) + '*' * (at - 2) + email.substring(at);
  }

  /// [비밀번호 찾기] 전화번호로 등록된 이메일에 재설정 메일 보내기
  /// 반환: 화면에 보여줄 안내 문구
  static Future<String> sendPasswordReset(String phone) async {
    final p = cleanPhone(phone);
    if (p.length < 10) return '전화번호를 정확히 입력해주세요.';
    try {
      final doc = await _db.collection('phone_index').doc(p).get();
      final email = doc.data()?['email'];
      if (email is! String || email.isEmpty) {
        return '해당 전화번호로 등록된 계정을 찾을 수 없습니다.\n관리자에게 문의하세요.';
      }
      if (email.endsWith('@f2telecom.com')) {
        return '실제 이메일 주소가 등록되어 있지 않습니다.\n관리자에게 문의하세요.';
      }
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return '${maskEmail(email)} 주소로\n비밀번호 재설정 메일을 보냈습니다.\n메일함(스팸함 포함)을 확인해 주세요.';
    } catch (e) {
      return '메일 발송 중 오류가 발생했습니다.\n$e';
    }
  }

  /// 본인 확인 (비밀번호·이메일 변경 전 현재 비밀번호로 다시 확인)
  static Future<String?> _reauth(String currentPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return '로그인 정보가 없습니다. 다시 로그인해주세요.';
    try {
      final cred = EmailAuthProvider.credential(email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
      return null;
    } on FirebaseAuthException catch (e) {
      if (['invalid-credential', 'wrong-password'].contains(e.code)) {
        return '현재 비밀번호가 맞지 않습니다.';
      }
      if (e.code == 'too-many-requests') {
        return '시도가 너무 많아 잠시 차단되었습니다. 잠시 후 다시 시도해주세요.';
      }
      return '본인 확인 실패: [${e.code}]';
    }
  }

  /// [비밀번호 변경] 성공 시 null, 실패 시 오류 문구
  static Future<String?> changePassword(String currentPassword, String newPassword) async {
    if (newPassword.length < 6) return '새 비밀번호는 6자리 이상이어야 합니다.';
    final err = await _reauth(currentPassword);
    if (err != null) return err;
    try {
      await FirebaseAuth.instance.currentUser!.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') return '비밀번호가 너무 쉽습니다. 영문/숫자를 섞어 6자리 이상으로 해주세요.';
      return '비밀번호 변경 실패: [${e.code}]';
    }
  }

  /// [이메일 변경] 새 주소로 인증 메일 발송 → 메일의 링크를 눌러야 실제로 바뀜
  /// 그동안은 기존 이메일·새 이메일 둘 다로 전화번호 로그인이 되도록 pendingEmail 저장
  static Future<String?> requestEmailChange(String currentPassword, String newEmail) async {
    final e = newEmail.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return '이메일 주소 형식이 올바르지 않습니다.';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '로그인 정보가 없습니다. 다시 로그인해주세요.';
    if (e == user.email) return '지금 사용 중인 이메일과 같습니다.';
    final err = await _reauth(currentPassword);
    if (err != null) return err;
    try {
      await user.verifyBeforeUpdateEmail(e);
    } on FirebaseAuthException catch (ex) {
      if (ex.code == 'email-already-in-use') return '이미 다른 계정에서 사용 중인 이메일입니다.';
      if (ex.code == 'invalid-email') return '이메일 주소 형식이 올바르지 않습니다.';
      return '이메일 변경 요청 실패: [${ex.code}]';
    }
    try {
      final udoc = await _db.collection('users').doc(user.uid).get();
      final phone = cleanPhone((udoc.data()?['phone'] ?? '').toString());
      await _db.collection('users').doc(user.uid).set({'pendingEmail': e}, SetOptions(merge: true));
      if (phone.isNotEmpty) {
        await _db.collection('phone_index').doc(phone).set(
            {'pendingEmail': e, 'uid': user.uid}, SetOptions(merge: true));
      }
    } catch (_) {}
    return null;
  }

  /// [로그아웃]
  static Future<void> logout() => clearSession(signOut: true);

  // ---------------- 3일 세션 ----------------

  /// 로그인(비밀번호 또는 생체인식) 성공 시 호출 → 3일 다시 시작
  static Future<void> markLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedIn, true);
    await prefs.setString(_kLastLogin, DateTime.now().toIso8601String());
  }

  /// 72시간 이내에 로그인한 기록이 있고 Firebase 로그인도 살아 있는지
  static Future<bool> isSessionValid() async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kLoggedIn) ?? false)) return false;
    final last = DateTime.tryParse(prefs.getString(_kLastLogin) ?? '');
    if (last == null) return false;
    return DateTime.now().difference(last).inHours < sessionHours;
  }

  /// 3일이 지났거나 로그아웃할 때
  static Future<void> clearSession({bool signOut = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedIn, false);
    await prefs.remove(_kLastLogin);
    if (signOut) await FirebaseAuth.instance.signOut();
  }

  /// 생체인식(지문/얼굴)으로 확인
  /// 반환: true = 통과, false = 취소/실패
  /// 화면 잠금(지문·얼굴·PIN·패턴)이 설정된 폰이면 항상 확인 창을 띄움
  /// (지문/얼굴 인식이 안 되면 PIN·패턴으로도 확인 가능)
  /// 화면 잠금 자체가 없는 폰만 확인 없이 통과(true)
  static Future<bool> unlockWithBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return true;

      return await _localAuth.authenticate(
        localizedReason: 'F2텔레콤 빠른 로그인을 위해 본인 확인을 진행합니다.',
        options: const AuthenticationOptions(
          biometricOnly: false, // 지문/얼굴 우선, 안 되면 PIN·패턴
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
