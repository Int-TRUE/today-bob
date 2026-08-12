import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrUploadScreen extends StatefulWidget {
  const OcrUploadScreen({super.key});

  @override
  State<OcrUploadScreen> createState() => _OcrUploadScreenState();
}

class _OcrUploadScreenState extends State<OcrUploadScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.korean,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    if (_isProcessing) return;

    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 95,
      maxWidth: 2200,
    );
    if (image == null || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final weeklyMenu = WeeklyMenuOcrParser().parse(recognizedText);
      if (!mounted) return;

      if (weeklyMenu.isReliable) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => OcrResultScreen(weeklyMenu: weeklyMenu),
          ),
        );
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const OcrFailureScreen()),
        );
      }
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
                    onPressed: _isProcessing
                        ? null
                        : () => _pickAndRecognize(ImageSource.camera),
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
                    onPressed: _isProcessing
                        ? null
                        : () => _pickAndRecognize(ImageSource.gallery),
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
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const OcrUploadScreen(),
                      ),
                    );
                  },
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
  const OcrResultScreen({super.key, required this.weeklyMenu});

  final WeeklyMenuOcrResult weeklyMenu;

  @override
  State<OcrResultScreen> createState() => _OcrResultScreenState();
}

class _OcrResultScreenState extends State<OcrResultScreen> {
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
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
            const SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: WeeklyMenuTable(result: widget.weeklyMenu),
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
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => const OcrUploadScreen(),
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
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('업로드 API는 다음 단계에서 연결합니다.'),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5A52),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
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
  const WeeklyMenuTable({super.key, required this.result});

  final WeeklyMenuOcrResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        children: [
          const BinderHoleRow(),
          const Divider(height: 1, color: Color(0xFF222222)),
          const SizedBox(
            height: 30,
            child: Row(
              children: [
                SizedBox(width: 60),
                Expanded(
                  child: Center(
                    child: Text('조식', style: TextStyle(fontSize: 12)),
                  ),
                ),
                VerticalDivider(width: 1, color: Color(0xFF222222)),
                Expanded(
                  child: Center(
                    child: Text('석식', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF222222)),
          ...result.days.map((day) => WeeklyMenuTableRow(dayMenu: day)),
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
  const WeeklyMenuTableRow({super.key, required this.dayMenu});

  final DayMenuOcrResult dayMenu;

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
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF222222)),
          Expanded(child: _MenuCell(items: dayMenu.breakfast)),
          const VerticalDivider(width: 1, color: Color(0xFF222222)),
          Expanded(child: _MenuCell(items: dayMenu.dinner)),
        ],
      ),
    );
  }
}

class _MenuCell extends StatelessWidget {
  const _MenuCell({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF222222))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items.take(7).map((item) {
          return Text(
            item,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.15,
              decoration: TextDecoration.underline,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class WeeklyMenuOcrParser {
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
        lines.where((line) => _weekdayLabels.contains(line.text)).toList()
          ..sort((a, b) => a.centerY.compareTo(b.centerY));

    final columnDivider = _columnDivider(lines);
    final rowAnchors = _rowAnchors(dayLines);
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
    final breakfastHeader = lines
        .where((line) => line.text.contains('조식'))
        .toList();
    final dinnerHeader = lines
        .where((line) => line.text.contains('석식') || line.text.contains('식식'))
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

  List<_RowAnchor> _rowAnchors(List<_OcrLine> dayLines) {
    if (dayLines.length >= 4) {
      return dayLines.map((line) {
        return _RowAnchor(weekday: line.text, centerY: line.centerY);
      }).toList();
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
    if (_weekdayLabels.contains(text)) return true;
    if (text.contains('생활관') || text.contains('식단표')) return true;
    if (text.contains('조식') || text.contains('석식')) return true;
    if (text.length <= 1) return true;
    return false;
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

  final List<DayMenuOcrResult> days;
  final String rawText;
  final int matchedDays;
  final int menuLineCount;

  bool get isReliable => matchedDays >= 4 && menuLineCount >= 12;
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

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
