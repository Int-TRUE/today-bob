import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:today_bob_app/services/meal_table_ocr_service.dart';

// 식단표 사진을 고르는 진입 화면입니다.
//
// 여기서는 “이미지를 얻고 OCR 서비스를 호출한 뒤 결과 화면으로 넘기는 일”만 맡고,
// 실제 표 검출/셀 분할/OCR 정리는 MealTableOcrService와 WeeklyMenuOcrResult가 처리합니다.
class OcrUploadScreen extends StatefulWidget {
  const OcrUploadScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<OcrUploadScreen> createState() => _OcrUploadScreenState();
}

class _OcrUploadScreenState extends State<OcrUploadScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final MealTableOcrService _mealTableOcrService = MealTableOcrService();
  bool _isProcessing = false;

  @override
  void dispose() {
    _mealTableOcrService.close();
    super.dispose();
  }

  Future<void> _openGuidedCamera() async {
    if (_isProcessing) return;

    final imagePath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const GuidedCameraCaptureScreen(),
      ),
    );
    if (imagePath == null || !mounted) return;

    await _recognizeImagePath(imagePath);
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;

    // 너무 큰 원본은 OCR 정확도보다 메모리 사용량에 부담이 커서 적당히 줄입니다.
    // 실제 표 분할 단계에서는 이 이미지 안에서 다시 perspective 보정이 일어납니다.
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 2200,
    );
    if (image == null || !mounted) return;

    await _recognizeImagePath(image.path);
  }

  Future<void> _recognizeImagePath(String imagePath) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await _mealTableOcrService.recognize(imagePath);
      final weeklyMenu = WeeklyMenuOcrResult.fromMealTableOcrResult(result);
      debugPrint(
        'Cell OCR matchedDays=${weeklyMenu.matchedDays}, '
        'menuLineCount=${weeklyMenu.menuLineCount}',
      );
      debugPrint('Cell OCR rawText=${weeklyMenu.rawText}');
      if (!mounted) return;

      // OCR이 완벽하지 않아도 일정 수준 이상이면 편집 화면으로 보냅니다.
      // 사용자가 직접 수정할 수 있으므로 “검토 가능한가”가 통과 기준입니다.
      if (weeklyMenu.canReview) {
        final didUpload = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => OcrResultScreen(
              weeklyMenu: weeklyMenu,
              deviceId: widget.deviceId,
            ),
          ),
        );
        if (didUpload == true && mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const OcrFailureScreen()),
        );
      }
    } on MealTableOcrException catch (error) {
      debugPrint('Meal table OCR failed: $error');
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const OcrFailureScreen()));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF222222),
              child: const Center(
                child: Icon(
                  Icons.document_scanner_outlined,
                  color: Color(0xFF777777),
                  size: 96,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                iconSize: 32,
                tooltip: '닫기',
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _isProcessing ? null : _openGuidedCamera,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEFEFEF),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFFEFEFEF),
                      fixedSize: const Size(72, 72),
                      side: const BorderSide(color: Colors.black, width: 2),
                    ),
                    iconSize: 42,
                    tooltip: '촬영',
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isProcessing ? null : _pickFromGallery,
                    child: const Text(
                      '앨범에서 선택',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GuidedCameraCaptureScreen extends StatefulWidget {
  const GuidedCameraCaptureScreen({super.key});

  @override
  State<GuidedCameraCaptureScreen> createState() =>
      _GuidedCameraCaptureScreenState();
}

class _GuidedCameraCaptureScreenState extends State<GuidedCameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  bool _isTakingPicture = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFuture = _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeFuture = _initializeCamera();
      setState(() {});
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', '사용 가능한 카메라가 없어요.');
      }

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller?.dispose();
      _controller = controller;
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.description ?? '카메라를 열지 못했어요.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _errorMessage = '카메라를 열지 못했어요.';
      });
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      final image = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(image.path);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _isTakingPicture = false;
        _errorMessage = error.description ?? '사진을 촬영하지 못했어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          final controller = _controller;
          final isReady =
              snapshot.connectionState == ConnectionState.done &&
              controller != null &&
              controller.value.isInitialized &&
              _errorMessage == null;

          return Stack(
            children: [
              Positioned.fill(
                child: isReady
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: _previewAspectRatio(controller),
                          child: CameraPreview(controller),
                        ),
                      )
                    : const ColoredBox(
                        color: Color(0xFF111111),
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
              ),
              Positioned.fill(
                child: CustomPaint(painter: MealTableGuidePainter()),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    iconSize: 32,
                    tooltip: '닫기',
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(68, 18, 68, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Text(
                          '표 전체를 선 안에 맞춰주세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_errorMessage != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage == null
                              ? '밝은 곳에서 종이가 화면을 크게 채우면 더 잘 인식돼요'
                              : '권한을 확인한 뒤 다시 시도해주세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        IconButton(
                          onPressed: isReady && !_isTakingPicture
                              ? _takePicture
                              : null,
                          icon: _isTakingPicture
                              ? const SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_outlined),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFEFEFEF),
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: const Color(0xFFBDBDBD),
                            fixedSize: const Size(72, 72),
                            side: const BorderSide(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          iconSize: 42,
                          tooltip: '촬영',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _previewAspectRatio(CameraController controller) {
    final cameraRatio = controller.value.aspectRatio;
    final mediaSize = MediaQuery.sizeOf(context);
    final isPortrait = mediaSize.height >= mediaSize.width;

    // 카메라 센서는 보통 가로 기준 비율을 돌려주기 때문에 세로 화면에서는 뒤집어서
    // 사용해야 촬영 화면과 가이드라인이 같은 방향으로 보입니다.
    if (isPortrait && cameraRatio > 1) {
      return 1 / cameraRatio;
    }
    if (!isPortrait && cameraRatio < 1) {
      return 1 / cameraRatio;
    }
    return cameraRatio;
  }
}

class MealTableGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final guideWidth = math.min(size.width * 0.82, size.height * 0.48);
    final guideHeight = math.min(size.height * 0.68, guideWidth * 1.58);
    final guideRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.48),
      width: guideWidth,
      height: guideHeight,
    );

    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.46)
      ..style = PaintingStyle.fill;
    final dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(guideRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, dimPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFFF726A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(guideRect, const Radius.circular(16)),
      borderPaint,
    );

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final weekdayX = guideRect.left + guideRect.width * 0.14;
    final mealDividerX = guideRect.left + guideRect.width * 0.50;
    _drawDashedLine(
      canvas,
      Offset(weekdayX, guideRect.top),
      Offset(weekdayX, guideRect.bottom),
      linePaint,
    );
    _drawDashedLine(
      canvas,
      Offset(mealDividerX, guideRect.top),
      Offset(mealDividerX, guideRect.bottom),
      linePaint,
    );

    for (var index = 1; index < 7; index += 1) {
      final y = guideRect.top + guideRect.height / 7 * index;
      _drawDashedLine(
        canvas,
        Offset(guideRect.left, y),
        Offset(guideRect.right, y),
        linePaint,
      );
    }

    _drawLabel(
      canvas,
      '요일',
      Offset(guideRect.left + guideRect.width * 0.07, guideRect.top + 24),
    );
    _drawLabel(
      canvas,
      '아침',
      Offset(guideRect.left + guideRect.width * 0.32, guideRect.top + 24),
    );
    _drawLabel(
      canvas,
      '저녁',
      Offset(guideRect.left + guideRect.width * 0.74, guideRect.top + 24),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 6.0;
    final vector = end - start;
    final distance = vector.distance;
    if (distance == 0) return;

    final direction = vector / distance;
    var drawn = 0.0;
    while (drawn < distance) {
      final next = math.min(drawn + dashLength, distance);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * next,
        paint,
      );
      drawn = next + gapLength;
    }
  }

  void _drawLabel(Canvas canvas, String label, Offset center) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.82),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy),
    );
  }

  @override
  bool shouldRepaint(covariant MealTableGuidePainter oldDelegate) => false;
}

class OcrFailureScreen extends StatelessWidget {
  const OcrFailureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const Text(
                '사진을 제대로 인식하지\n못했어요.\n\n다시 촬영해주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFA7A7A7),
                  fontSize: 24,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 5),
              SizedBox(
                width: double.infinity,
                height: 62,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Color(0xFFE1E1E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('뒤로  가기', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 62,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5A52),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('다시 촬영하기', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(height: 38),
            ],
          ),
        ),
      ),
    );
  }
}

class OcrResultScreen extends StatefulWidget {
  const OcrResultScreen({
    super.key,
    required this.weeklyMenu,
    required this.deviceId,
    this.uploadApiClient = const MenuUploadApiClient(),
  });

  final WeeklyMenuOcrResult weeklyMenu;
  final String deviceId;
  final MenuUploadApiClient uploadApiClient;

  @override
  State<OcrResultScreen> createState() => _OcrResultScreenState();
}

class _OcrResultScreenState extends State<OcrResultScreen> {
  late DateTime _startDate;
  late WeeklyMenuOcrResult _weeklyMenu;
  var _isUploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _startDate = _mondayOf(DateTime.now());
    _weeklyMenu = widget.weeklyMenu.copy();
  }

  Future<void> _pickStartDate() async {
    final firstMonday = _mondayOf(DateTime.now());
    final lastMonday = firstMonday.add(const Duration(days: 14));
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: firstMonday,
      lastDate: lastMonday,
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
      helpText: '시작일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked == null) return;

    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _uploadError = null;
    });
  }

  Future<void> _handleUpload() async {
    if (_startDate.weekday != DateTime.monday) {
      setState(() {
        _uploadError = '시작일은 월요일이어야 해요.';
      });
      return;
    }

    if (_weeklyMenu.hasEmptyMenuCell) {
      setState(() {
        _uploadError = '비어 있는 식단을 모두 입력해주세요.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      await widget.uploadApiClient.uploadWeek(
        startDate: _startDate,
        weeklyMenu: _weeklyMenu,
        deviceId: widget.deviceId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('식단이 등록됐어요.')));
      Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() {
        _uploadError = '식단 등록에 실패했어요. 서버가 실행 중인지 확인해주세요.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _updateMenuCell(int dayIndex, OcrMealColumn column, List<String> items) {
    setState(() {
      final day = _weeklyMenu.days[dayIndex];
      final target = column == OcrMealColumn.breakfast
          ? day.breakfast
          : day.dinner;
      target
        ..clear()
        ..addAll(items);
      _uploadError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final endDate = _startDate.add(const Duration(days: 6));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 46),
            const Text('이렇게 업로드 할까요?', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 24),
            const Text(
              '시작일 선택',
              style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 16),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pickStartDate,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                side: const BorderSide(color: Color(0xFF9E9E9E)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                '${_startDate.month}월 ${_startDate.day}일',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_startDate.month}월 ${_startDate.day}일부터 '
              '${endDate.month}월 ${endDate.day}일까지',
              style: const TextStyle(fontSize: 16),
            ),
            if (_uploadError != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Text(
                  _uploadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF5A52),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  children: [
                    WeeklyMenuTable(
                      result: _weeklyMenu,
                      onMenuChanged: _updateMenuCell,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 18, 34, 22),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: OutlinedButton(
                        onPressed: _isUploading
                            ? null
                            : () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) => OcrUploadScreen(
                                      deviceId: widget.deviceId,
                                    ),
                                  ),
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Color(0xFFE1E1E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '재촬영',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: FilledButton(
                        onPressed: _isUploading ? null : _handleUpload,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5A52),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '이렇게 업로드!',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeeklyMenuTable extends StatelessWidget {
  const WeeklyMenuTable({
    super.key,
    required this.result,
    required this.onMenuChanged,
  });

  final WeeklyMenuOcrResult result;
  final void Function(int dayIndex, OcrMealColumn column, List<String> items)
  onMenuChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E1E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const BinderHoleRow(),
          const Divider(height: 1, color: Color(0xFF3A3A3A)),
          const SizedBox(
            height: 30,
            child: Row(
              children: [
                SizedBox(width: 60),
                Expanded(
                  child: Center(
                    child: Text(
                      '아침',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: Color(0xFF3A3A3A)),
                Expanded(
                  child: Center(
                    child: Text(
                      '저녁',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3A3A3A)),
          ...result.days.indexed.map((entry) {
            return WeeklyMenuTableRow(
              dayIndex: entry.$1,
              dayMenu: entry.$2,
              onMenuChanged: onMenuChanged,
            );
          }),
        ],
      ),
    );
  }
}

class BinderHoleRow extends StatelessWidget {
  const BinderHoleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          6,
          (_) => Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF5F5F5),
            ),
          ),
        ),
      ),
    );
  }
}

class WeeklyMenuTableRow extends StatelessWidget {
  const WeeklyMenuTableRow({
    super.key,
    required this.dayIndex,
    required this.dayMenu,
    required this.onMenuChanged,
  });

  final int dayIndex;
  final DayMenuOcrResult dayMenu;
  final void Function(int dayIndex, OcrMealColumn column, List<String> items)
  onMenuChanged;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 60,
            child: Center(
              child: Text(
                dayMenu.weekday,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF3A3A3A)),
          Expanded(
            child: _MenuCell(
              items: dayMenu.breakfast,
              onChanged: (items) {
                onMenuChanged(dayIndex, OcrMealColumn.breakfast, items);
              },
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF3A3A3A)),
          Expanded(
            child: _MenuCell(
              items: dayMenu.dinner,
              onChanged: (items) {
                onMenuChanged(dayIndex, OcrMealColumn.dinner, items);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCell extends StatelessWidget {
  const _MenuCell({required this.items, required this.onChanged});

  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  Future<void> _editItems(BuildContext context) async {
    final controller = TextEditingController(text: items.join('\n'));
    final editedItems = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('메뉴 수정'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 5,
            maxLines: 9,
            decoration: const InputDecoration(
              hintText: '메뉴를 한 줄에 하나씩 입력',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(<String>[]),
              child: const Text('비우기'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final nextItems = controller.text
                    .split(RegExp(r'\r?\n'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList();
                Navigator.of(context).pop(nextItems);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (editedItems != null) {
      onChanged(editedItems);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _editItems(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 94),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF3A3A3A))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: items.isEmpty
              ? const [
                  Text(
                    '메뉴 추가',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFF5A52),
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ]
              : items.take(7).map((item) {
                  return Text(
                    item,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.18,
                      decoration: TextDecoration.underline,
                    ),
                  );
                }).toList(),
        ),
      ),
    );
  }
}

enum OcrMealColumn { breakfast, dinner }

class MenuUploadApiClient {
  const MenuUploadApiClient({this.baseUrl});

  final String? baseUrl;

  Future<void> uploadWeek({
    required DateTime startDate,
    required WeeklyMenuOcrResult weeklyMenu,
    required String deviceId,
  }) async {
    final uri = Uri.parse('${baseUrl ?? _defaultBaseUrl()}/api/menus/week');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      // 서버는 승인된 기기만 주간 식단을 저장할 수 있게 이 헤더를 검사합니다.
      request.headers.set('x-device-id', deviceId);
      request.write(
        jsonEncode({
          'startDate': _apiDate(startDate),
          'days': weeklyMenu.days.map((day) {
            return {
              'weekday': day.weekday,
              'breakfast': day.breakfast,
              'dinner': day.dinner,
            };
          }).toList(),
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(body, uri: uri);
      }
    } finally {
      client.close(force: true);
    }
  }
}

class WeeklyMenuOcrParser {
  // 예전 방식의 전체 이미지 OCR 파서입니다.
  //
  // 현재 주 흐름은 MealTableOcrService가 셀 14개를 나눠 OCR하지만, 이 파서는
  // OCR 결과가 전체 텍스트로만 들어오는 경우를 대비한 fallback/테스트 자산으로 남겨둡니다.
  WeeklyMenuOcrResult parse(RecognizedText recognizedText) {
    final lines = <_OcrLine>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = _normalize(line.text);
        if (text.isEmpty) continue;
        lines.add(_OcrLine(text: text, rect: line.boundingBox));
      }
    }

    final dayLines =
        lines.where((line) => _weekdayLabelFor(line.text) != null).toList()
          ..sort((a, b) => a.centerY.compareTo(b.centerY));

    final columnDivider = _columnDivider(lines);
    final rowAnchors = _rowAnchors(lines, dayLines);
    final days = _weekdayLabels
        .map((label) => DayMenuOcrResult(weekday: label))
        .toList();

    for (final line in lines) {
      if (_shouldSkip(line.text)) continue;

      final dayIndex = _dayIndexFor(line.centerY, rowAnchors);
      if (dayIndex == null || dayIndex < 0 || dayIndex >= days.length) continue;

      final target = line.centerX < columnDivider
          ? days[dayIndex].breakfast
          : days[dayIndex].dinner;
      if (!target.contains(line.text)) {
        target.add(line.text);
      }
    }

    final matchedDays = days
        .where((day) => day.breakfast.isNotEmpty || day.dinner.isNotEmpty)
        .length;
    final menuLineCount = days.fold<int>(
      0,
      (count, day) => count + day.breakfast.length + day.dinner.length,
    );

    return WeeklyMenuOcrResult(
      days: days,
      rawText: recognizedText.text,
      matchedDays: matchedDays,
      menuLineCount: menuLineCount,
    );
  }

  double _columnDivider(List<_OcrLine> lines) {
    // 표의 세로 구분선을 직접 찾기 어렵다면 “조식/석식” 헤더 위치나
    // 메뉴 텍스트의 좌우 분포를 이용해 아침/저녁 경계를 추정합니다.
    final breakfastHeader = lines
        .where((line) => line.text.contains('조식'))
        .toList();
    final dinnerHeader = lines
        .where(
          (line) =>
              line.text.contains('석식') ||
              line.text.contains('식식') ||
              line.text.contains('적식'),
        )
        .toList();

    if (breakfastHeader.isNotEmpty && dinnerHeader.isNotEmpty) {
      return (breakfastHeader.first.centerX + dinnerHeader.first.centerX) / 2;
    }

    final menuCenters = lines
        .where((line) => !_shouldSkip(line.text))
        .map((line) => line.centerX)
        .toList();
    if (menuCenters.length < 2) return 0;

    return (menuCenters.reduce(math.min) + menuCenters.reduce(math.max)) / 2;
  }

  List<_RowAnchor> _rowAnchors(List<_OcrLine> lines, List<_OcrLine> dayLines) {
    // 요일 글자가 정확히 인식되면 그 위치를 행 기준점으로 사용합니다.
    // 일부만 인식되면 간격을 보간하고, 전혀 없으면 메뉴 텍스트 분포로 추정합니다.
    if (dayLines.length >= _weekdayLabels.length) {
      return dayLines.take(_weekdayLabels.length).indexed.map((entry) {
        return _RowAnchor(
          weekday: _weekdayLabelFor(entry.$2.text) ?? _weekdayLabels[entry.$1],
          centerY: entry.$2.centerY,
        );
      }).toList();
    }

    if (dayLines.length >= 2) {
      final sortedDayLines = [...dayLines]
        ..sort((a, b) => a.centerY.compareTo(b.centerY));
      final gaps = <double>[];
      for (var index = 1; index < sortedDayLines.length; index += 1) {
        gaps.add(
          sortedDayLines[index].centerY - sortedDayLines[index - 1].centerY,
        );
      }
      gaps.sort();

      final rowGap = gaps[gaps.length ~/ 2];
      final firstLabel = _weekdayLabelFor(sortedDayLines.first.text);
      final firstLabelIndex = math.max(
        0,
        _weekdayLabels.indexOf(firstLabel ?? _weekdayLabels.first),
      );
      final firstRowY = sortedDayLines.first.centerY - rowGap * firstLabelIndex;

      return List.generate(_weekdayLabels.length, (index) {
        return _RowAnchor(
          weekday: _weekdayLabels[index],
          centerY: firstRowY + rowGap * index,
        );
      });
    }

    final menuLines = lines.where((line) => !_shouldSkip(line.text)).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    if (menuLines.length >= _weekdayLabels.length) {
      final minY = menuLines.first.centerY;
      final maxY = menuLines.last.centerY;
      final rowGap = (maxY - minY) / (_weekdayLabels.length - 1);

      return List.generate(_weekdayLabels.length, (index) {
        return _RowAnchor(
          weekday: _weekdayLabels[index],
          centerY: minY + rowGap * index,
        );
      });
    }

    return List.generate(7, (index) {
      return _RowAnchor(
        weekday: _weekdayLabels[index],
        centerY: index.toDouble(),
      );
    });
  }

  int? _dayIndexFor(double centerY, List<_RowAnchor> anchors) {
    if (anchors.isEmpty) return null;

    var closest = anchors.first;
    var closestDistance = (centerY - closest.centerY).abs();
    for (final anchor in anchors.skip(1)) {
      final distance = (centerY - anchor.centerY).abs();
      if (distance < closestDistance) {
        closest = anchor;
        closestDistance = distance;
      }
    }

    return _weekdayLabels.indexOf(closest.weekday);
  }

  bool _shouldSkip(String text) {
    if (_weekdayLabelFor(text) != null) return true;
    if (text.contains('생활관') || text.contains('식단표')) return true;
    if (text.contains('조식') || text.contains('석식') || text.contains('적식')) {
      return true;
    }
    if (text.length <= 1) return true;
    return false;
  }

  String? _weekdayLabelFor(String text) {
    final normalized = text.trim();
    if (_weekdayLabels.contains(normalized)) return normalized;

    const fuzzyWeekdayLabels = {
      '원': '월',
      '왈': '월',
      '와': '화',
      '하': '화',
      '수.': '수',
      '숙': '수',
      '묵': '목',
      '득': '목',
      '금.': '금',
      '토.': '토',
      '일.': '일',
    };
    return fuzzyWeekdayLabels[normalized];
  }

  String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('ㆍ', '.')
        .replaceAll('|', '/')
        .trim();
  }
}

class WeeklyMenuOcrResult {
  const WeeklyMenuOcrResult({
    required this.days,
    required this.rawText,
    required this.matchedDays,
    required this.menuLineCount,
  });

  factory WeeklyMenuOcrResult.fromMealTableOcrResult(
    MealTableOcrResult result,
  ) {
    final days = _weekdayLabels
        .map((label) => DayMenuOcrResult(weekday: label))
        .toList();

    for (final cell in result.cells) {
      if (cell.dayIndex < 0 || cell.dayIndex >= days.length) continue;
      final target = cell.mealType == MealType.breakfast
          ? days[cell.dayIndex].breakfast
          : days[cell.dayIndex].dinner;
      target
        ..clear()
        ..addAll(cell.menus);
    }

    final matchedDays = days
        .where((day) => day.breakfast.isNotEmpty || day.dinner.isNotEmpty)
        .length;
    final menuLineCount = days.fold<int>(
      0,
      (count, day) => count + day.breakfast.length + day.dinner.length,
    );

    return WeeklyMenuOcrResult(
      days: days,
      rawText: result.rawText,
      matchedDays: matchedDays,
      menuLineCount: menuLineCount,
    );
  }

  final List<DayMenuOcrResult> days;
  final String rawText;
  final int matchedDays;
  final int menuLineCount;

  bool get isReliable => matchedDays >= 4 && menuLineCount >= 12;

  bool get canReview {
    // 인식률이 낮아도 원문 라인이 충분하면 사용자가 편집으로 살릴 수 있으므로
    // 실패 화면 대신 결과 화면에 진입시킵니다.
    final rawLineCount = rawText
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().length > 1)
        .length;
    return isReliable || (menuLineCount >= 8 && rawLineCount >= 8);
  }

  bool get hasEmptyMenuCell {
    return days.any((day) => day.breakfast.isEmpty || day.dinner.isEmpty);
  }

  WeeklyMenuOcrResult copy() {
    return WeeklyMenuOcrResult(
      days: days.map((day) => day.copy()).toList(),
      rawText: rawText,
      matchedDays: matchedDays,
      menuLineCount: menuLineCount,
    );
  }
}

class DayMenuOcrResult {
  DayMenuOcrResult({
    required this.weekday,
    List<String>? breakfast,
    List<String>? dinner,
  }) : breakfast = breakfast ?? <String>[],
       dinner = dinner ?? <String>[];

  final String weekday;
  final List<String> breakfast;
  final List<String> dinner;

  DayMenuOcrResult copy() {
    return DayMenuOcrResult(
      weekday: weekday,
      breakfast: [...breakfast],
      dinner: [...dinner],
    );
  }
}

class _OcrLine {
  const _OcrLine({required this.text, required this.rect});

  final String text;
  final Rect rect;

  double get centerX => rect.center.dx;
  double get centerY => rect.center.dy;
}

class _RowAnchor {
  const _RowAnchor({required this.weekday, required this.centerY});

  final String weekday;
  final double centerY;
}

DateTime _mondayOf(DateTime date) {
  final stripped = DateTime(date.year, date.month, date.day);
  return stripped.subtract(Duration(days: stripped.weekday - 1));
}

String _apiDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _defaultBaseUrl() {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (Platform.isAndroid) return 'http://10.0.2.2:3000';
  return 'http://127.0.0.1:3000';
}

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
