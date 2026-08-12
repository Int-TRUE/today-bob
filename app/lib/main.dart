import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  runApp(const TodayBobApp());
}

class TodayBobApp extends StatelessWidget {
  const TodayBobApp({super.key, this.apiClient});

  final HomeApiClient? apiClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘밥',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF5A52)),
        fontFamily: 'NEXONLv1Gothic',
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: HomeScreen(apiClient: apiClient ?? HomeApiClient()),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.apiClient});

  final HomeApiClient apiClient;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late DateTime _selectedDate;
  late DateTime _weekStart;
  HomeData? _homeData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = _stripTime(now);
    _weekStart = _mondayOf(now);
    _loadHome();
  }

  Future<void> _loadHome() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await widget.apiClient.fetchHome(_selectedDate);
      if (!mounted) return;
      setState(() {
        _homeData = data;
        _isLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _homeData = HomeData.empty(_selectedDate);
        _isLoading = false;
      });
    }
  }

  void _moveDate(int days) {
    final nextDate = _selectedDate.add(Duration(days: days));
    if (nextDate.isBefore(_weekStart) ||
        nextDate.isAfter(_weekStart.add(const Duration(days: 6)))) {
      return;
    }

    setState(() {
      _selectedDate = nextDate;
    });
    _loadHome();
  }

  Future<void> _handleUploadPressed() async {
    final hasMenu = _homeData?.hasMenu ?? false;

    if (hasMenu) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('이미 식단이 있어요'),
            content: const Text('오늘 식단이 조회됩니다. 그래도 이번 주 식단을 업로드할까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('업로드'),
              ),
            ],
          );
        },
      );

      if (shouldContinue != true || !mounted) return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CameraPlaceholderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _homeData ?? HomeData.empty(_selectedDate);
    final canGoPrevious = _selectedDate.isAfter(_weekStart);
    final canGoNext = _selectedDate.isBefore(
      _weekStart.add(const Duration(days: 6)),
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 393),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 39),
                child: Column(
                  children: [
                    const SizedBox(height: 44),
                    DateHeader(
                      date: _selectedDate,
                      canGoPrevious: canGoPrevious,
                      canGoNext: canGoNext,
                      onPrevious: () => _moveDate(-1),
                      onNext: () => _moveDate(1),
                    ),
                    const SizedBox(height: 18),
                    MealCard(
                      isLoading: _isLoading,
                      hasMenu: data.hasMenu,
                      menuItems: data.menuItems,
                    ),
                    const SizedBox(height: 36),
                    MarqueeMessage(text: data.message),
                    const SizedBox(height: 16),
                    OperatingHoursPill(
                      mealLabel: data.mealLabel,
                      timeLabel: data.operatingHoursLabel,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 62,
                      child: FilledButton(
                        onPressed: _handleUploadPressed,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5A52),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '이번주 식단 업로드',
                            style: TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DateHeader extends StatelessWidget {
  const DateHeader({
    super.key,
    required this.date,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime date;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _DateArrowButton(
              icon: Icons.arrow_left_rounded,
              enabled: canGoPrevious,
              onPressed: onPrevious,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${date.month}월 ${date.day}일',
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _weekdayLabel(date),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),
            _DateArrowButton(
              icon: Icons.arrow_right_rounded,
              enabled: canGoNext,
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
      ],
    );
  }
}

class _DateArrowButton extends StatelessWidget {
  const _DateArrowButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      color: const Color(0xFFFF5A52),
      disabledColor: const Color(0xFFFFD2CF),
      iconSize: 42,
      visualDensity: VisualDensity.compact,
      tooltip: icon == Icons.arrow_left_rounded ? '이전날' : '다음날',
    );
  }
}

class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.isLoading,
    required this.hasMenu,
    required this.menuItems,
  });

  final bool isLoading;
  final bool hasMenu;
  final List<String> menuItems;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 443,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            top: 22,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE8E8E8)),
                color: Colors.white,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 17),
                  const BinderHoles(),
                  Expanded(child: _buildContent()),
                ],
              ),
            ),
          ),
          const Positioned(top: 0, child: TomatoPin()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF5A52)),
      );
    }

    if (!hasMenu) {
      return const EmptyMealMessage();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 48, 22, 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: menuItems.map((item) {
            return Text(
              item,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 24,
                height: 1.15,
                color: Colors.black,
                fontFamily: 'KyoboHandwriting2025',
                fontWeight: FontWeight.w500,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class BinderHoles extends StatelessWidget {
  const BinderHoles({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        6,
        (_) => Container(
          width: 21,
          height: 21,
          decoration: const BoxDecoration(
            color: Color(0xFFF5F5F5),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class TomatoPin extends StatelessWidget {
  const TomatoPin({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 48,
      child: SvgPicture.asset('assets/images/tomato.svg', fit: BoxFit.contain),
    );
  }
}

class EmptyMealMessage extends StatelessWidget {
  const EmptyMealMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '오늘 밥 뭐야?\nㅠ_ㅠ\n\n아직 식단이\n등록되지 않았어요!\n\n아래 식단 업로드 버튼을 눌러\n사진을 찍어주세요!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFA7A7A7),
                fontSize: 24,
                height: 1.38,
                fontFamily: 'KyoboHandwriting2025',
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 28),
            const Icon(
              Icons.arrow_downward_rounded,
              color: Color(0xFFD9D9D9),
              size: 68,
            ),
          ],
        ),
      ),
    );
  }
}

class MarqueeMessage extends StatefulWidget {
  const MarqueeMessage({super.key, required this.text});

  final String text;

  @override
  State<MarqueeMessage> createState() => _MarqueeMessageState();
}

class _MarqueeMessageState extends State<MarqueeMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FractionalTranslation(
              translation: Offset(1 - (_controller.value * 2), 0),
              child: child,
            );
          },
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              color: Color(0xFFB2B2B2),
              fontSize: 14,
              fontFamily: 'KyoboHandwriting2025',
            ),
          ),
        ),
      ),
    );
  }
}

class OperatingHoursPill extends StatelessWidget {
  const OperatingHoursPill({
    super.key,
    required this.mealLabel,
    required this.timeLabel,
  });

  final String mealLabel;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 63,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF777777), width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD0CD),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  mealLabel,
                  style: const TextStyle(fontSize: 24, color: Colors.black),
                ),
              ),
            ),
          ),
          const SizedBox(width: 19),
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                timeLabel,
                style: const TextStyle(fontSize: 24, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraPlaceholderScreen extends StatelessWidget {
  const CameraPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('식단 업로드')),
      body: const Center(
        child: Text(
          'OCR 카메라 화면은 다음 단계에서 연결합니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

class HomeApiClient {
  HomeApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  final String baseUrl;

  Future<HomeData> fetchHome(DateTime date) async {
    final uri = Uri.parse('$baseUrl/api/home').replace(
      queryParameters: {
        'date': _apiDate(date),
        'at': DateTime.now().toIso8601String(),
      },
    );
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(body, uri: uri);
      }

      return HomeData.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  static String _defaultBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }
}

class HomeData {
  const HomeData({
    required this.date,
    required this.mealType,
    required this.mealLabel,
    required this.menuItems,
    required this.message,
    required this.operatingHoursLabel,
  });

  final DateTime date;
  final String mealType;
  final String mealLabel;
  final List<String> menuItems;
  final String message;
  final String operatingHoursLabel;

  bool get hasMenu => menuItems.isNotEmpty;

  factory HomeData.fromJson(Map<String, dynamic> json) {
    final menu = json['menu'] as Map<String, dynamic>? ?? {};
    final hours = json['operatingHours'] as Map<String, dynamic>? ?? {};

    return HomeData(
      date: DateTime.parse(json['date'] as String),
      mealType: menu['type'] as String? ?? 'dinner',
      mealLabel: _mealLabel(menu['type'] as String? ?? 'dinner'),
      menuItems: (menu['items'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      message: json['message'] as String? ?? '',
      operatingHoursLabel: hours['label'] as String? ?? '-',
    );
  }

  factory HomeData.empty(DateTime date) {
    return HomeData(
      date: date,
      mealType: 'dinner',
      mealLabel: '저녁',
      menuItems: const [],
      message: '제가 가장 좋아하는 메뉴는 계란말이 입니다.',
      operatingHoursLabel: '18:00 ~ 19:00',
    );
  }
}

String _mealLabel(String type) => type == 'breakfast' ? '조식' : '저녁';

String _apiDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _weekdayLabel(DateTime date) {
  const labels = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  return labels[date.weekday - 1];
}

DateTime _stripTime(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _mondayOf(DateTime date) {
  final stripped = _stripTime(date);
  return stripped.subtract(Duration(days: stripped.weekday - 1));
}
