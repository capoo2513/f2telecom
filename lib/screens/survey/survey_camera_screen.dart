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
  final String? rootFolder; // 사진첩 폴더 (기본 F2실사, 개통은 F2개통)
  final String? stamp; // 갤러리 저장본 위쪽에 새길 글자 (개통 선번 등, 없으면 안 새김)

  const SurveyCameraScreen({
    super.key,
    required this.station,
    required this.baseName,
    required this.label,
    required this.startNumber,
    this.rootFolder,
    this.stamp,
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
  double _zoom = 1; // 확대 배율 (0.6X / 1X / 2X / 3X)
  double _maxZoom = 1;
  double _minZoom = 1; // 1 보다 작으면 광각(0.6X 등) 가능한 폰
  List<CameraDescription> _backs = []; // 뒤 카메라 목록 (광각 렌즈가 따로 잡히는 폰 대비)
  int _camIdx = 0; // 지금 쓰는 뒤 카메라 번호 (0 = 기본)
  bool _wideByLens = false; // true: 광각을 다른 렌즈로 바꿔서 쓰는 중
  Offset? _focusAt; // 눌러서 초점 맞춘 자리 (화면에 잠깐 네모 표시)

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
      _backs = cams.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      if (_backs.isEmpty) _backs = [cams.first];
      if (_camIdx >= _backs.length) _camIdx = 0;
      final back = _backs[_camIdx];
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      double maxZ = 1;
      double minZ = 1;
      try {
        maxZ = await c.getMaxZoomLevel();
      } catch (_) {}
      try {
        minZ = await c.getMinZoomLevel();
      } catch (_) {}
      // 자동 초점·자동 노출 (기본 카메라처럼 계속 초점을 맞춤)
      try {
        await c.setFocusMode(FocusMode.auto);
        await c.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      setState(() {
        _ctrl = c;
        _error = null;
        _maxZoom = maxZ;
        _minZoom = minZ;
        _zoom = _wideByLens ? _wideMark : 1;
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
        folder: widget.rootFolder,
        stamp: widget.stamp,
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

  /// 화면을 눌러 그 자리에 초점·밝기 맞추기
  Future<void> _tapFocus(TapUpDetails d, BoxConstraints box) async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    final p = Offset(
      (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
      (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
    );
    setState(() => _focusAt = d.localPosition);
    try {
      if (c.value.focusPointSupported) {
        await c.setFocusMode(FocusMode.auto);
        await c.setFocusPoint(p);
      }
      if (c.value.exposurePointSupported) await c.setExposurePoint(p);
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusAt = null);
    });
  }

  static const double _wideMark = 0.6; // 광각 버튼 표시용

  /// 이 폰에서 광각을 쓸 수 있는지
  ///  1) 배율을 1 아래로 내릴 수 있는 폰 → 그 배율(0.6X 등)
  ///  2) 광각이 다른 렌즈로 따로 잡히는 폰 → 렌즈 바꾸기
  bool get _hasWide => _minZoom < 0.95 || _backs.length > 1;

  /// 렌즈 바꾸기 (광각 렌즈 ↔ 기본 렌즈)
  Future<void> _switchLens(int idx, {required bool wide}) async {
    final old = _ctrl;
    setState(() {
      _ctrl = null;
      _camIdx = idx;
      _wideByLens = wide;
    });
    await old?.dispose();
    await _init();
  }

  /// 배율 바꾸기: 0.6X(광각) / 1X / 2X / 3X
  Future<void> _setZoom(double z) async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    // 광각
    if (z < 1) {
      if (_minZoom < 0.95) {
        try {
          await c.setZoomLevel(_minZoom);
          if (mounted) setState(() => _zoom = z);
        } catch (e) {
          _zoomError(e);
        }
      } else if (_backs.length > 1) {
        await _switchLens(_camIdx == 0 ? 1 : 0, wide: _camIdx == 0);
      }
      return;
    }
    // 광각 렌즈로 바꿔 둔 상태면 기본 렌즈로 돌아온 뒤 확대
    if (_wideByLens) {
      await _switchLens(0, wide: false);
      if (z == 1) return;
    }
    final cc = _ctrl;
    if (cc == null || !cc.value.isInitialized) return;
    final v = z > _maxZoom ? _maxZoom : z;
    try {
      await cc.setZoomLevel(v);
      if (mounted) setState(() => _zoom = z);
    } catch (e) {
      _zoomError(e);
    }
  }

  void _zoomError(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('배율 변경 실패: $e')));
  }

  String _zoomText(double z) {
    if (z < 1) {
      // 배율로 되는 폰은 실제 최소 배율 (예: 0.6X, 0.5X), 렌즈 바꾸는 폰은 '광각'
      return _minZoom < 0.95 ? '${_minZoom.toStringAsFixed(1)}X' : '광각';
    }
    return '${z.toInt()}X';
  }

  Widget _zoomBar() {
    final levels = <double>[if (_hasWide) _wideMark, 1.0, 2.0, 3.0];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final z in levels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Opacity(
              opacity: z <= _maxZoom || z < 1 ? 1 : 0.35,
              child: GestureDetector(
                onTap: z <= _maxZoom || z < 1 ? () => _setZoom(z) : null,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _zoom == z ? Colors.amber : Colors.white24,
                  ),
                  child: Text(_zoomText(z),
                      style: TextStyle(
                          color: _zoom == z ? Colors.black : Colors.white,
                          fontSize: z < 1 ? 13 : 15,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

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
                                // 화면을 누르면 그 자리에 초점
                                CameraPreview(
                                  c,
                                  child: LayoutBuilder(
                                    builder: (ctx, box) => GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (d) => _tapFocus(d, box),
                                      child: Stack(children: [
                                        if (_focusAt != null)
                                          Positioned(
                                            left: _focusAt!.dx - 36,
                                            top: _focusAt!.dy - 36,
                                            child: IgnorePointer(
                                              child: Container(
                                                width: 72,
                                                height: 72,
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: Colors.amber, width: 2),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ]),
                                    ),
                                  ),
                                ),
                                if (_flash)
                                  Positioned.fill(
                                    child: Container(color: Colors.white70),
                                  ),
                              ],
                            ),
                ),
              ),
              // 확대 버튼 (1X · 2X · 3X) — 촬영 버튼 바로 위
              if (c != null && c.value.isInitialized)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _zoomBar(),
                ),
              if (_lastName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                      '저장됨: DCIM/${widget.rootFolder ?? SurveyPhotoService.rootFolder}/${SurveyPhotoService.safeName(widget.station)}/$_lastName',
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
