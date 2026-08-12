import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:today_bob_app/ocr_upload_screen.dart';

void main() {
  test('parses weekly menu lines by weekday and column', () {
    final recognizedText = RecognizedText.fromJson({
      'text': '',
      'blocks': [
        {
          'text': '',
          'rect': _rect(0, 0),
          'recognizedLanguages': [],
          'points': [],
          'lines': [
            _line('조식', 150, 90),
            _line('석식', 290, 90),
            _line('월', 60, 150),
            _line('에그샌드위치', 150, 150),
            _line('우유/과일쥬스', 150, 170),
            _line('콩나물밥/부추양념장', 290, 150),
            _line('소고기우거지국', 290, 170),
            _line('화', 60, 250),
            _line('유부초밥', 150, 250),
            _line('어묵탕', 150, 270),
            _line('돈까정', 290, 250),
            _line('달걀야채말이/케찹', 290, 270),
            _line('수', 60, 350),
            _line('베이컨샌드위치', 150, 350),
            _line('북어국', 150, 370),
            _line('김밥', 290, 350),
            _line('컵라면', 290, 370),
            _line('목', 60, 450),
            _line('치킨까스샌드위치', 150, 450),
            _line('배추국', 150, 470),
            _line('마파두부덮밥', 290, 450),
            _line('계란국', 290, 470),
          ],
        },
      ],
    });

    final result = WeeklyMenuOcrParser().parse(recognizedText);

    expect(result.isReliable, isTrue);
    expect(result.days[0].breakfast, contains('에그샌드위치'));
    expect(result.days[0].dinner, contains('콩나물밥/부추양념장'));
    expect(result.days[3].breakfast, contains('치킨까스샌드위치'));
    expect(result.days[3].dinner, contains('마파두부덮밥'));
  });
}

Map<String, double> _rect(double centerX, double centerY) {
  return {
    'left': centerX - 10,
    'top': centerY - 5,
    'right': centerX + 10,
    'bottom': centerY + 5,
  };
}

Map<String, Object?> _line(String text, double centerX, double centerY) {
  return {
    'text': text,
    'rect': _rect(centerX, centerY),
    'recognizedLanguages': [],
    'points': [],
    'confidence': null,
    'angle': null,
    'elements': [],
  };
}
