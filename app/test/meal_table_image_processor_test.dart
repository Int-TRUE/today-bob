import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:today_bob_app/services/meal_table_ocr_service.dart';

void main() {
  test('extracts 14 meal cell images from the sample table photo', () async {
    final sample = File('/Users/sujin/Downloads/IMG_4063.JPG');
    if (!sample.existsSync()) return;

    final cells = await const MealTableImageProcessor().extractCellImages(
      sample.path,
    );

    expect(cells, hasLength(14));
    expect(cells.map((cell) => cell.index), List.generate(14, (i) => i + 1));
    expect(cells.first.dayIndex, 0);
    expect(cells.first.mealType, MealType.breakfast);
    expect(cells[1].mealType, MealType.dinner);
    for (final cell in cells) {
      expect(File(cell.path).existsSync(), isTrue);
    }
  });
}
