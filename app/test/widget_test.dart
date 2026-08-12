import 'package:flutter_test/flutter_test.dart';

import 'package:today_bob_app/main.dart';

void main() {
  testWidgets('renders app shell', (WidgetTester tester) async {
    await tester.pumpWidget(TodayBobApp(apiClient: FakeHomeApiClient()));
    await tester.pump();

    expect(find.textContaining('월'), findsWidgets);
    expect(find.text('길거리토스트'), findsOneWidget);
    expect(find.text('이번주 식단 업로드'), findsOneWidget);
  });
}

class FakeHomeApiClient implements HomeApiClient {
  @override
  String get baseUrl => 'http://example.test';

  @override
  Future<HomeData> fetchHome(DateTime date) async {
    return HomeData(
      date: date,
      mealType: 'dinner',
      mealLabel: '저녁',
      menuItems: const ['길거리토스트', '우유/요구르트'],
      message: '테스트 문구',
      operatingHoursLabel: '18:00 ~ 19:00',
    );
  }
}
