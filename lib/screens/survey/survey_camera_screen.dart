import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'survey_photo_service.dart';

/// 앱 안 연속 촬영 카메라
/// 셔터를 누를 때마다 1장씩 저장되고, [완료]를 누르면 찍은 사진 목록을 돌려줍니다.
class SurveyCameraScreen extends StatefulWidget {
  final String station;
  final String baseName; // 파일명 가운데 부분 (예: 정류기1_정류기 전면)
  final String label; // 화면 위 안내 (예: 정류기1 · 정류기 전면)
  final int startNumber; // 이 항목의 다음 사진 번호

  const SurveyCameraScreen({
    super.key,
    required this.station,
    required this.baseName,
    required this.label,
    required this.startNumber,
  });

  @override
  State<SurveyCameraScreen> createState() => _SurveyCameraScreenState();
}

class _SurveyCameraScreenState extends State<SurveyCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _initializing = false;
  bool _busy = false;
  bool _flash = false; // 촬영 순간 화면 깜빡임
  bool _feedbackWarned = false;
  String? _error;
  static const _feedbackChannel = MethodChannel('f2telecom/camera');
  final List<String> _taken = [];
  String _lastName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _error = '사용할 수 있는 카메라가 없습니다.');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctrl = c;
        _error = null;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('AccessDenied')
            ? '카메라 권한이 거부되었습니다.\n휴대폰 설정 > 애플리케이션 > F2텔레콤 > 권한에서 카메라를 허용해주세요.'
            : '카메라 오류: ${e.description ?? e.code}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '카메라 오류: $e');
    } finally {
      _initializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final c = _ctrl;
      if (c != null) {
        _ctrl = null;
        c.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_ctrl == null && _error == null) _init();
    }
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() {
      _busy = true;
      _flash = true;
    });
    _shutterFeedback();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flash = false);
    });
    try {
      final shot = await c.takePicture();
      final res = await SurveyPhotoService.saveCaptured(
        srcPath: shot.path,
        station: widget.station,
        baseName: widget.baseName,
        number: widget.startNumber + _taken.length,
      );
      _taken.add(res.path);
      _lastName = res.path.split('/').last;
      if (res.galleryError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('갤러리 저장 실패 (앱에는 추가됨): ${res.galleryError}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('촬영 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 찰칵 소리 + 진동 (휴대폰 기본 셔터음)
  Future<void> _shutterFeedback() async {
    String status;
    try {
      status = await _feedbackChannel.invokeMethod<String>('shutter') ?? 'null';
    } catch (e) {
      status = '안드로이드 기능 호출 실패: $e';
    }
    if (status == 'ok') return;
    // 안드로이드 쪽 기능을 못 쓰면 기본 소리/진동이라도
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
    if (!_feedbackWarned && mounted) {
      _feedbackWarned = true; // 처음 한 번만 알림
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('셔터음/진동 문제: $status')));
    }
  }

  void _done() => Navigator.pop(context, _taken);

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _done(); // 뒤로가기 = 완료 (찍은 사진 유지)
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('카메라 · 연속 촬영',
                              style: TextStyle(color: Colors.white60, fontSize: 13)),
                          Text(widget.label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70)),
                        )
                      : (c == null || !c.value.isInitialized)
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                CameraPreview(c),
                                if (_flash)
                                  Positioned.fill(
                                    child: Container(color: Colors.white70),
                                  ),
                              ],
                            ),
                ),
              ),
              if (_lastName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                      '저장됨: Pictures/${SurveyPhotoService.rootFolder}/${SurveyPhotoService.safeName(widget.station)}/$_lastName',
                      style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                ),
              SizedBox(
                height: 130,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    SizedBox(
                      width: 90,
                      child: _taken.isEmpty
                          ? const Text('0장 촬영',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 15))
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(File(_taken.last),
                                      width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 120),
                                ),
                                const SizedBox(height: 4),
                                Text('${_taken.length}장 촬영',
                                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                              ],
                            ),
                    ),
                    Semantics(
                      button: true,
                      label: '촬영',
                      child: GestureDetector(
                        onTap: _shoot,
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _busy ? Colors.grey : Colors.white,
                            border: Border.all(color: Colors.white70, width: 5),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextButton(
                        onPressed: _done,
                        child: const Text('완료',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
