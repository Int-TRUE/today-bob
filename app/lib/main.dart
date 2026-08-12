import 'package:flutter/material.dart';

void main() {
  runApp(const TodayBobApp());
}

class TodayBobApp extends StatelessWidget {
  const TodayBobApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘밥',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('오늘밥')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(
              '오늘 생활관 식단을 한눈에',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Figma 디자인과 API 요구사항을 연결할 준비가 됐어요.',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: () {}, child: const Text('식단 불러오기')),
          ],
        ),
      ),
    );
  }
}
