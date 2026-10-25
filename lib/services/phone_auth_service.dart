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
  /// 휴대폰에 생체인식 기능이나 등록된 지문이 없으면 확인 없이 통과(true)
  static Future<bool> unlockWithBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final enrolled = canCheck ? await _localAuth.getAvailableBiometrics() : <BiometricType>[];
      if (!supported || enrolled.isEmpty) return true;

      return await _localAuth.authenticate(
        localizedReason: 'F2텔레콤 빠른 로그인을 위해 생체인증을 진행합니다.',
        options: const AuthenticationOptions(
          biometricOnly: true,
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
