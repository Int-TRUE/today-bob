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

  test('infers seven rows when weekday labels are not recognized', () {
    final lines = <Map<String, Object?>>[
      _line('조식', 150, 90),
      _line('석식', 290, 90),
    ];
    for (var index = 0; index < 7; index += 1) {
      final centerY = 150.0 + index * 100;
      lines.add(_line('아침${index + 1}', 150, centerY));
      lines.add(_line('국${index + 1}', 150, centerY + 18));
      lines.add(_line('저녁${index + 1}', 290, centerY));
      lines.add(_line('반찬${index + 1}', 290, centerY + 18));
    }

    final recognizedText = RecognizedText.fromJson({
      'text': '',
      'blocks': [
        {
          'text': '',
          'rect': _rect(0, 0),
          'recognizedLanguages': [],
          'points': [],
          'lines': lines,
        },
      ],
    });

    final result = WeeklyMenuOcrParser().parse(recognizedText);

    expect(result.isReliable, isTrue);
    expect(result.days[0].breakfast, contains('아침1'));
    expect(result.days[0].dinner, contains('저녁1'));
    expect(result.days[6].breakfast, contains('아침7'));
    expect(result.days[6].dinner, contains('저녁7'));
  });

  test('accepts common OCR mistakes in weekday and dinner labels', () {
    final recognizedText = RecognizedText.fromJson({
      'text': [
        '생활관식단표',
        '조식',
        '적식',
        '월',
        '에그샌드위치',
        '콩나물밥/부추양념장',
        '와',
        '유부초밥',
        '돈개장',
        '수',
        '베이컨샌드위치',
        '김밥',
        '목',
        '치킨까스샌드위지',
        '마파두부덮밥',
        '금',
        '길거리토스토',
        '안방삼계탕',
        '토',
        '스테이크샌드위치',
        '오꼬노미야끼',
        '일',
        '김밥',
        '삼겹살김치볶음/온두부',
      ].join('\n'),
      'blocks': [
        {
          'text': '',
          'rect': _rect(0, 0),
          'recognizedLanguages': [],
          'points': [],
          'lines': [
            _line('생활관식단표', 200, 40),
            _line('조식', 150, 90),
            _line('적식', 290, 90),
            _line('월', 60, 150),
            _line('에그샌드위치', 150, 150),
            _line('콩나물밥/부추양념장', 290, 150),
            _line('와', 60, 250),
            _line('유부초밥', 150, 250),
            _line('돈개장', 290, 250),
            _line('수', 60, 350),
            _line('베이컨샌드위치', 150, 350),
            _line('김밥', 290, 350),
            _line('목', 60, 450),
            _line('치킨까스샌드위지', 150, 450),
            _line('마파두부덮밥', 290, 450),
            _line('금', 60, 550),
            _line('길거리토스토', 150, 550),
            _line('안방삼계탕', 290, 550),
            _line('토', 60, 650),
            _line('스테이크샌드위치', 150, 650),
            _line('오꼬노미야끼', 290, 650),
            _line('일', 60, 750),
            _line('김밥', 150, 750),
            _line('삼겹살김치볶음/온두부', 290, 750),
          ],
        },
      ],
    });

    final result = WeeklyMenuOcrParser().parse(recognizedText);

    expect(result.canReview, isTrue);
    expect(result.days[1].weekday, '화');
    expect(result.days[1].breakfast, contains('유부초밥'));
    expect(result.days[1].dinner, contains('돈개장'));
    expect(result.days[3].breakfast, contains('치킨까스샌드위지'));
    expect(result.days[6].dinner, contains('삼겹살김치볶음/온두부'));
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
