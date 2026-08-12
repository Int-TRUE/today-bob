import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:today_bob_app/main.dart';

void main() {
  testWidgets('renders app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const TodayBobApp());

    expect(find.text('오늘밥'), findsWidgets);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
