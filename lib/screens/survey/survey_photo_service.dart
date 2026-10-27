import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class TakenPhoto {
  final String path;
  final String? galleryError; // null 이면 갤러리 저장 성공
  TakenPhoto(this.path, this.galleryError);
}

/// 실사 사진 저장 / 갤러리 선택
///
/// 카메라로 찍은 사진은
///   휴대폰 사진 > DCIM/F2실사(개통은 F2개통)/<국소명>/ 폴더에
///   "<국소명>_<섹션>_<사진명>_<번호>.jpg" 이름으로 저장됩니다.
/// 앱에서 쓰는 사본은 앱 폴더(survey/<국소명>/)에 보관되어 임시저장 후에도 남습니다.
class SurveyPhotoService {
  static const _channel = MethodChannel('f2telecom/gallery');
  static const String rootFolder = 'F2실사';
  static final ImagePicker _picker = ImagePicker();

  /// 파일/폴더 이름에 쓸 수 없는 문자 정리
  static String safeName(String s) {
    return s
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  static Future<Directory> _workDir(String station) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/survey/${safeName(station)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> _uniquePath(Directory dir, String fileName) async {
    String path = '${dir.path}/$fileName';
    if (await File(path).exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final dot = fileName.lastIndexOf('.');
      final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
      final ext = dot > 0 ? fileName.substring(dot) : '.jpg';
      path = '${dir.path}/${stem}_$stamp$ext';
    }
    return path;
  }

  /// 앱 카메라로 찍은 사진 1장 → 이름 바꿔 보관 + 갤러리(국소명 폴더)에 저장
  static Future<TakenPhoto> saveCaptured({
    required String srcPath,
    required String station,
    required String baseName, // 예: 정류기1_정류기_전면
    required int number,
    String? folder, // 사진첩 폴더 (기본 F2실사, 개통은 F2개통)
    String? stamp, // 갤러리 저장본 위쪽에 새길 글자 (앱 보관본은 원본 그대로)
  }) async {
    final stationSafe = safeName(station);
    final fileName =
        '${stationSafe}_${safeName(baseName)}_${number.toString().padLeft(2, '0')}.jpg';

    final dir = await _workDir(station);
    final destPath = await _uniquePath(dir, fileName);
    await File(srcPath).copy(destPath);
    try {
      await File(srcPath).delete(); // 카메라 임시파일 정리
    } catch (_) {}

    String? galleryError;
    try {
      await _channel.invokeMethod('saveImage', {
        'path': destPath,
        'album': '${folder ?? rootFolder}/$stationSafe',
        'name': destPath.split('/').last,
        'label': stamp ?? '',
      });
    } catch (e) {
      // 갤러리 저장에 실패해도 앱(밴드 업로드)에서는 계속 사용 가능
      galleryError = e.toString();
    }
    return TakenPhoto(destPath, galleryError);
  }

  /// [개통 센싱] 휴대폰 스크린샷 폴더를 바로 열어 여러 장 선택 → 앱 폴더로 복사
  ///   안드로이드 쪽 기능을 못 쓰면 일반 갤러리 선택으로 대신
  static Future<List<String>> pickScreenshots(String station) async {
    List<String> picked;
    try {
      final res = await const MethodChannel('f2telecom/picker').invokeMethod<List<dynamic>>('pickScreenshots');
      picked = (res ?? const []).map((e) => e.toString()).toList();
    } catch (_) {
      return pickFromGallery(station);
    }
    if (picked.isEmpty) return [];
    final dir = await _workDir(station);
    final out = <String>[];
    for (var i = 0; i < picked.length; i++) {
      final dest = await _uniquePath(dir, 'sensing_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
      await File(picked[i]).copy(dest);
      try {
        await File(picked[i]).delete();
      } catch (_) {}
      out.add(dest);
    }
    return out;
  }

  /// 갤러리에서 여러 장 선택 → 앱 폴더로 복사 (임시저장 후에도 사진이 남도록)
  static Future<List<String>> pickFromGallery(String station) async {
    final List<XFile> files = await _picker.pickMultiImage();
    if (files.isEmpty) return [];
    final dir = await _workDir(station);
    final out = <String>[];
    for (final f in files) {
      final name = 'gallery_${safeName(f.name.isNotEmpty ? f.name : 'photo.jpg')}';
      final dest = await _uniquePath(dir, name);
      await File(f.path).copy(dest);
      out.add(dest);
    }
    return out;
  }
}
