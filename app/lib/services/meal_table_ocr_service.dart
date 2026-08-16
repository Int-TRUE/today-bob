import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

enum MealType { breakfast, dinner }

// OCR 최종 단위입니다.
//
// index는 화면/디버그에서 보이는 1~14 순번이고, dayIndex는 월~일을 0~6으로
// 다룹니다. mealType은 왼쪽 열 아침, 오른쪽 열 저녁을 나타냅니다.
class MealCell {
  const MealCell({
    required this.index,
    required this.dayIndex,
    required this.mealType,
    required this.menus,
  });

  final int index;
  final int dayIndex;
  final MealType mealType;
  final List<String> menus;
}

class MealTableOcrResult {
  const MealTableOcrResult({required this.cells, required this.rawText});

  final List<MealCell> cells;
  final String rawText;
}

class MealTableOcrException implements Exception {
  const MealTableOcrException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MealTableOcrService {
  MealTableOcrService({TextRecognizer? textRecognizer})
    : _textRecognizer =
          textRecognizer ??
          TextRecognizer(script: TextRecognitionScript.korean);

  final TextRecognizer _textRecognizer;
  final MealTableImageProcessor _imageProcessor =
      const MealTableImageProcessor();

  Future<MealTableOcrResult> recognize(String imagePath) async {
    // 처리 순서:
    // 원본 이미지 -> 표 검출 -> perspective 보정 -> 14개 셀 crop -> 셀별 한국어 OCR
    final cellImages = await _imageProcessor.extractCellImages(imagePath);
    final cells = <MealCell>[];
    final rawTexts = <String>[];

    for (final cellImage in cellImages) {
      final recognizedText = await _textRecognizer.processImage(
        InputImage.fromFilePath(cellImage.path),
      );
      final menus = _menusFromRecognizedText(recognizedText);
      rawTexts.add(_cellDebugText(cellImage, menus, recognizedText.text));
      cells.add(
        MealCell(
          index: cellImage.index,
          dayIndex: cellImage.dayIndex,
          mealType: cellImage.mealType,
          menus: menus,
        ),
      );
    }

    return MealTableOcrResult(cells: cells, rawText: rawTexts.join('\n'));
  }

  Future<void> close() => _textRecognizer.close();

  List<String> _menusFromRecognizedText(RecognizedText recognizedText) {
    // ML Kit은 block/line 단위 순서를 항상 표의 시각적 순서로 보장하지 않으므로
    // boundingBox.top 기준으로 다시 정렬해 메뉴 순서를 안정화합니다.
    final lines = <_RecognizedMenuLine>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = _normalizeMenu(line.text);
        if (text.isEmpty) continue;
        if (_shouldSkipMenuText(text)) continue;
        lines.add(_RecognizedMenuLine(text: text, top: line.boundingBox.top));
      }
    }

    lines.sort((a, b) => a.top.compareTo(b.top));
    final menus = <String>[];
    for (final line in lines) {
      if (!menus.contains(line.text)) {
        menus.add(line.text);
      }
    }
    return menus;
  }

  String _cellDebugText(
    CellImage cellImage,
    List<String> menus,
    String rawText,
  ) {
    const dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
    final zeroBasedIndex = cellImage.index - 1;
    final dayLabel = dayLabels[cellImage.dayIndex];
    final mealLabel = cellImage.mealType == MealType.breakfast ? '아침' : '저녁';
    final menuText = menus.isEmpty
        ? '(empty)'
        : menus.map((menu) => '- $menu').join('\n');
    final raw = rawText.trim().isEmpty ? '(empty)' : rawText.trim();

    return [
      '[$zeroBasedIndex] cell=${cellImage.index} $dayLabel $mealLabel',
      'menus:',
      menuText,
      'raw:',
      raw,
    ].join('\n');
  }

  String _normalizeMenu(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('ㆍ', '.')
        .replaceAll('|', '/')
        .trim();
  }

  bool _shouldSkipMenuText(String text) {
    if (text.contains('생활관') || text.contains('식단표')) return true;
    if (text.contains('조식')) return true;
    if (text.contains('석식') || text.contains('식식') || text.contains('적식')) {
      return true;
    }
    return false;
  }
}

class MealTableImageProcessor {
  const MealTableImageProcessor();

  Future<List<CellImage>> extractCellImages(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const MealTableOcrException('이미지를 읽을 수 없어요.');
    }

    final source = img.bakeOrientation(decoded);
    if (math.min(source.width, source.height) < 600) {
      throw const MealTableOcrException('식단표 사진이 너무 작아요.');
    }

    // 내부 선을 매번 완벽히 찾기보다, 전체 표를 먼저 펴고 고정 레이아웃
    // 비율로 나누는 전략입니다. 촬영 각도가 조금 달라도 비교적 안정적입니다.
    final tableQuad = TableDetector().detect(source);
    final corrected = PerspectiveCorrector().correct(source, tableQuad);
    return MealGridCropper().crop(corrected);
  }
}

// 사진 안에서 식단표 전체 사각형을 찾습니다.
//
// 현재 식단표는 검은 표 선이 뚜렷하므로 긴 가로선을 찾고, 가장 위/아래
// 가로선을 표의 경계로 사용합니다. 실패하면 촬영 샘플에 맞춘 보수적 fallback을 씁니다.
class TableDetector {
  TableQuad detect(img.Image source) {
    final scale = source.width > 1000 ? 1000 / source.width : 1.0;
    final image = scale < 1
        ? img.copyResize(source, width: (source.width * scale).round())
        : source;
    final mask = _darkMask(image);
    final horizontalLines = _horizontalLineCandidates(mask, image.width).where((
      line,
    ) {
      return line.y > image.height * 0.10 &&
          line.y < image.height * 0.985 &&
          line.startX < image.width * 0.24 &&
          line.endX > image.width * 0.68;
    }).toList();

    if (horizontalLines.length < 4) {
      return _fallbackQuad(source);
    }

    final top = horizontalLines.first;
    final bottom = horizontalLines.last;
    if ((bottom.y - top.y) < image.height * 0.45) {
      return _fallbackQuad(source);
    }

    return TableQuad(
      topLeft: _scalePoint(
        TablePoint(top.startX.toDouble(), top.y.toDouble()),
        1 / scale,
      ),
      topRight: _scalePoint(
        TablePoint(top.endX.toDouble(), top.y.toDouble()),
        1 / scale,
      ),
      bottomRight: _scalePoint(
        TablePoint(bottom.endX.toDouble(), bottom.y.toDouble()),
        1 / scale,
      ),
      bottomLeft: _scalePoint(
        TablePoint(bottom.startX.toDouble(), bottom.y.toDouble()),
        1 / scale,
      ),
    );
  }

  List<List<bool>> _darkMask(img.Image image) {
    final mask = List.generate(
      image.height,
      (_) => List<bool>.filled(image.width, false),
    );
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        final pixel = image.getPixel(x, y);
        final luma = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
        mask[y][x] = luma < 125;
      }
    }
    return mask;
  }

  List<_LineCandidate> _horizontalLineCandidates(
    List<List<bool>> mask,
    int width,
  ) {
    final candidates = <_LineCandidate>[];
    var y = 0;
    while (y < mask.length) {
      final rowWidth = _darkRunWidth(mask, y);
      if (rowWidth.width < width * 0.45) {
        y += 1;
        continue;
      }

      var bestY = y;
      var bestRun = rowWidth;
      var endY = y;
      while (endY + 1 < mask.length) {
        final nextRun = _darkRunWidth(mask, endY + 1);
        if (nextRun.width < width * 0.45) break;
        endY += 1;
        if (nextRun.width > bestRun.width) {
          bestRun = nextRun;
          bestY = endY;
        }
      }

      candidates.add(
        _LineCandidate(y: bestY, startX: bestRun.startX, endX: bestRun.endX),
      );
      y = endY + 1;
    }

    if (candidates.length <= 10) return candidates;

    final merged = <_LineCandidate>[];
    for (final candidate in candidates) {
      if (merged.isNotEmpty && candidate.y - merged.last.y < 12) {
        final previous = merged.removeLast();
        merged.add(
          _LineCandidate(
            y: ((previous.y + candidate.y) / 2).round(),
            startX: math.min(previous.startX, candidate.startX),
            endX: math.max(previous.endX, candidate.endX),
          ),
        );
      } else {
        merged.add(candidate);
      }
    }
    return merged;
  }

  _DarkRun _darkRunWidth(List<List<bool>> mask, int y) {
    final projection = List<bool>.filled(mask[y].length, false);
    for (var dy = -2; dy <= 2; dy += 1) {
      final yy = y + dy;
      if (yy < 0 || yy >= mask.length) continue;
      for (var x = 0; x < mask[yy].length; x += 1) {
        projection[x] = projection[x] || mask[yy][x];
      }
    }

    var bestStart = 0;
    var bestEnd = 0;
    var currentStart = -1;
    var gap = 0;
    for (var x = 0; x < projection.length; x += 1) {
      if (projection[x]) {
        currentStart = currentStart < 0 ? x : currentStart;
        gap = 0;
      } else if (currentStart >= 0) {
        gap += 1;
        if (gap > 10) {
          final currentEnd = x - gap;
          if (currentEnd - currentStart > bestEnd - bestStart) {
            bestStart = currentStart;
            bestEnd = currentEnd;
          }
          currentStart = -1;
          gap = 0;
        }
      }
    }

    if (currentStart >= 0 &&
        projection.length - 1 - currentStart > bestEnd - bestStart) {
      bestStart = currentStart;
      bestEnd = projection.length - 1;
    }

    return _DarkRun(startX: bestStart, endX: bestEnd);
  }

  TableQuad _fallbackQuad(img.Image source) {
    // 표 검출이 실패해도 앱이 죽지 않도록, 사진 중앙의 “대략 종이 영역”을 사용합니다.
    final marginX = source.width * 0.08;
    final marginTop = source.height * 0.14;
    final marginBottom = source.height * 0.04;
    return TableQuad(
      topLeft: TablePoint(marginX, marginTop),
      topRight: TablePoint(source.width - marginX, marginTop),
      bottomRight: TablePoint(
        source.width - marginX,
        source.height - marginBottom,
      ),
      bottomLeft: TablePoint(marginX, source.height - marginBottom),
    );
  }
}

// 비스듬히 찍힌 표를 정면에서 본 것처럼 펴는 단계입니다.
//
// 네 모서리의 대응 관계로 homography 행렬을 만들고, 출력 이미지의 각 픽셀이
// 원본 이미지의 어느 위치에서 와야 하는지 역으로 샘플링합니다.
class PerspectiveCorrector {
  img.Image correct(img.Image source, TableQuad quad) {
    final topWidth = quad.topLeft.distanceTo(quad.topRight);
    final bottomWidth = quad.bottomLeft.distanceTo(quad.bottomRight);
    final leftHeight = quad.topLeft.distanceTo(quad.bottomLeft);
    final rightHeight = quad.topRight.distanceTo(quad.bottomRight);
    final outputWidth = ((topWidth + bottomWidth) / 2).round().clamp(700, 1200);
    final outputHeight = ((leftHeight + rightHeight) / 2).round().clamp(
      1000,
      1800,
    );
    final matrix = _homography(
      [
        const TablePoint(0, 0),
        TablePoint(outputWidth - 1, 0),
        TablePoint(outputWidth - 1, outputHeight - 1),
        TablePoint(0, outputHeight - 1),
      ],
      [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft],
    );
    final corrected = img.Image(width: outputWidth, height: outputHeight);

    for (var y = 0; y < outputHeight; y += 1) {
      for (var x = 0; x < outputWidth; x += 1) {
        final denominator = matrix[6] * x + matrix[7] * y + 1;
        final sourceX =
            (matrix[0] * x + matrix[1] * y + matrix[2]) / denominator;
        final sourceY =
            (matrix[3] * x + matrix[4] * y + matrix[5]) / denominator;
        final pixel = _sampleBilinear(source, sourceX, sourceY);
        corrected.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, pixel.a);
      }
    }

    return corrected;
  }

  List<double> _homography(List<TablePoint> from, List<TablePoint> to) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i += 1) {
      final x = from[i].x;
      final y = from[i].y;
      final u = to[i].x;
      final v = to[i].y;
      a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }

    for (var col = 0; col < 8; col += 1) {
      var pivot = col;
      for (var row = col + 1; row < 8; row += 1) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      final temp = a[col];
      a[col] = a[pivot];
      a[pivot] = temp;

      final divisor = a[col][col];
      if (divisor.abs() < 1e-8) {
        throw const MealTableOcrException('표 보정에 실패했어요.');
      }
      for (var item = col; item < 9; item += 1) {
        a[col][item] /= divisor;
      }

      for (var row = 0; row < 8; row += 1) {
        if (row == col) continue;
        final factor = a[row][col];
        for (var item = col; item < 9; item += 1) {
          a[row][item] -= factor * a[col][item];
        }
      }
    }

    return List.generate(8, (index) => a[index][8]);
  }

  img.Color _sampleBilinear(img.Image image, double x, double y) {
    final clampedX = x.clamp(0, image.width - 1).toDouble();
    final clampedY = y.clamp(0, image.height - 1).toDouble();
    final x0 = clampedX.floor();
    final y0 = clampedY.floor();
    final x1 = math.min(x0 + 1, image.width - 1);
    final y1 = math.min(y0 + 1, image.height - 1);
    final dx = clampedX - x0;
    final dy = clampedY - y0;

    final p00 = image.getPixel(x0, y0);
    final p10 = image.getPixel(x1, y0);
    final p01 = image.getPixel(x0, y1);
    final p11 = image.getPixel(x1, y1);

    num channel(num a, num b, num c, num d) {
      return a * (1 - dx) * (1 - dy) +
          b * dx * (1 - dy) +
          c * (1 - dx) * dy +
          d * dx * dy;
    }

    return img.ColorRgba8(
      channel(p00.r, p10.r, p01.r, p11.r).round(),
      channel(p00.g, p10.g, p01.g, p11.g).round(),
      channel(p00.b, p10.b, p01.b, p11.b).round(),
      channel(p00.a, p10.a, p01.a, p11.a).round(),
    );
  }
}

class MealGridCropper {
  List<CellImage> crop(img.Image tableImage) {
    final cells = <CellImage>[];
    final grid = _detectGrid(tableImage);
    final cellHeight = (grid.bottom - grid.top) / 7;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'today_bob_cells_',
    );

    for (var dayIndex = 0; dayIndex < 7; dayIndex += 1) {
      for (var columnIndex = 0; columnIndex < 2; columnIndex += 1) {
        final index = dayIndex * 2 + columnIndex + 1;
        final columnLeft = columnIndex == 0 ? grid.left : grid.center;
        final columnRight = columnIndex == 0 ? grid.center : grid.right;
        final cellWidth = columnRight - columnLeft;
        // 셀 테두리 선이 OCR 텍스트로 섞이지 않도록 약간 안쪽만 잘라냅니다.
        final insetX = (cellWidth * 0.045).round();
        final insetY = (cellHeight * 0.04).round();
        final cropX = columnLeft + insetX;
        final cropY = (grid.top + cellHeight * dayIndex).round() + insetY;
        final cropWidth = (cellWidth - insetX * 2).round();
        final cropHeight = (cellHeight - insetY * 2).round();
        final cellImage = img.copyCrop(
          tableImage,
          x: cropX.clamp(0, tableImage.width - 1),
          y: cropY.clamp(0, tableImage.height - 1),
          width: cropWidth.clamp(1, tableImage.width - cropX),
          height: cropHeight.clamp(1, tableImage.height - cropY),
        );
        final processed = _preprocessForOcr(cellImage);
        final path = '${tempDirectory.path}/cell_$index.jpg';
        File(path).writeAsBytesSync(img.encodeJpg(processed, quality: 95));
        cells.add(
          CellImage(
            path: path,
            index: index,
            dayIndex: dayIndex,
            mealType: columnIndex == 0 ? MealType.breakfast : MealType.dinner,
          ),
        );
      }
    }

    return cells;
  }

  _MealGrid _detectGrid(img.Image image) {
    // perspective 보정 후에는 표 비율이 거의 고정되므로, 요일 열을 제외한
    // 식단 영역의 좌/중앙/우 위치를 비율로 잡습니다. 아래쪽은 검출된 마지막
    // 가로선에 맞춰 잘라 일요일 영역이 너무 짧아지지 않게 합니다.
    final mask = _darkMask(image);
    final horizontals = _lineCenters(
      List.generate(image.height, (y) {
        var count = 0;
        for (var x = 0; x < image.width; x += 1) {
          if (mask[y][x]) count += 1;
        }
        return count / image.width;
      }),
      threshold: 0.22,
    );

    final left = (image.width * 0.085).round();
    final center = (image.width * 0.455).round();
    final right = (image.width * 0.91).round();
    final top = (image.height * 0.04).round();
    final bottom = _pickClosest(
      horizontals,
      image.height * 0.98,
      fallback: (image.height * 0.99).round(),
    );

    if (center <= left ||
        center >= right ||
        right - left < image.width * 0.55 ||
        bottom - top < image.height * 0.55) {
      return _fallbackGrid(image);
    }

    return _MealGrid(
      left: left,
      center: center,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  _MealGrid _fallbackGrid(img.Image image) {
    return _MealGrid(
      left: (image.width * 0.09).round(),
      center: (image.width * 0.455).round(),
      top: (image.height * 0.08).round(),
      right: (image.width * 0.91).round(),
      bottom: (image.height * 0.99).round(),
    );
  }

  List<List<bool>> _darkMask(img.Image image) {
    final mask = List.generate(
      image.height,
      (_) => List<bool>.filled(image.width, false),
    );
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        final pixel = image.getPixel(x, y);
        final luma = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
        mask[y][x] = luma < 135;
      }
    }
    return mask;
  }

  List<int> _lineCenters(List<double> projection, {required double threshold}) {
    final centers = <int>[];
    var start = -1;
    var bestIndex = 0;
    var bestValue = 0.0;

    for (var index = 0; index < projection.length; index += 1) {
      final value = projection[index];
      if (value >= threshold) {
        if (start < 0) {
          start = index;
          bestIndex = index;
          bestValue = value;
        } else if (value > bestValue) {
          bestIndex = index;
          bestValue = value;
        }
      } else if (start >= 0) {
        if (index - start >= 1) centers.add(bestIndex);
        start = -1;
        bestValue = 0;
      }
    }

    if (start >= 0) centers.add(bestIndex);
    return centers;
  }

  int _pickClosest(List<int> values, double target, {required int fallback}) {
    if (values.isEmpty) return fallback;
    return values.reduce((a, b) {
      return (a - target).abs() < (b - target).abs() ? a : b;
    });
  }

  img.Image _preprocessForOcr(img.Image source) {
    final resized = source.width < 450
        ? img.copyResize(source, width: 450)
        : source;
    final result = img.Image(width: resized.width, height: resized.height);
    for (var y = 0; y < resized.height; y += 1) {
      for (var x = 0; x < resized.width; x += 1) {
        final pixel = resized.getPixel(x, y);
        final luma = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114)
            .round()
            .clamp(0, 255);
        result.setPixelRgb(x, y, luma, luma, luma);
      }
    }
    return img.adjustColor(result, contrast: 1.18);
  }
}

class CellImage {
  const CellImage({
    required this.path,
    required this.index,
    required this.dayIndex,
    required this.mealType,
  });

  final String path;
  final int index;
  final int dayIndex;
  final MealType mealType;
}

class _MealGrid {
  const _MealGrid({
    required this.left,
    required this.center,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int center;
  final int top;
  final int right;
  final int bottom;
}

class TableQuad {
  const TableQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final TablePoint topLeft;
  final TablePoint topRight;
  final TablePoint bottomRight;
  final TablePoint bottomLeft;
}

class TablePoint {
  const TablePoint(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(TablePoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

TablePoint _scalePoint(TablePoint point, double scale) {
  return TablePoint(point.x * scale, point.y * scale);
}

class _LineCandidate {
  const _LineCandidate({
    required this.y,
    required this.startX,
    required this.endX,
  });

  final int y;
  final int startX;
  final int endX;
}

class _DarkRun {
  const _DarkRun({required this.startX, required this.endX});

  final int startX;
  final int endX;

  int get width => endX - startX;
}

class _RecognizedMenuLine {
  const _RecognizedMenuLine({required this.text, required this.top});

  final String text;
  final double top;
}
