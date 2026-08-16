import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_upload_screen.dart';

void main() {
  runApp(const TodayBobApp());
}

// 앱의 최상위 조립 지점입니다.
//
// 테스트에서는 아래 세 클라이언트를 가짜 구현으로 주입하고, 실제 앱에서는
// 서버 API/기기 ID 저장소를 기본 구현으로 사용합니다.
class TodayBobApp extends StatelessWidget {
  const TodayBobApp({
    super.key,
    this.apiClient,
    this.deviceApprovalClient,
    this.deviceIdentityStore,
  });

  final HomeApiClient? apiClient;
  final DeviceApprovalApiClient? deviceApprovalClient;
  final DeviceIdentityStore? deviceIdentityStore;

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
      home: DeviceApprovalGate(
        approvalClient: deviceApprovalClient ?? DeviceApprovalApiClient(),
        identityStore: deviceIdentityStore ?? DeviceIdentityStore(),
        homeBuilder: (_, deviceId) => HomeScreen(
          apiClient: apiClient ?? HomeApiClient(),
          deviceId: deviceId,
        ),
      ),
    );
  }
}

// 승인 게이트는 앱 첫 화면을 결정합니다.
//
// - 등록되지 않은 기기: 가입 신청 화면
// - 승인 대기 기기: 입력값이 잠긴 신청 완료 화면
// - 승인된 기기: 실제 홈 화면
//
// 식단 업로드 API도 같은 deviceId를 요구하므로, 승인된 deviceId를 HomeScreen까지
// 내려보내는 것이 이 흐름의 핵심입니다.
class DeviceApprovalGate extends StatefulWidget {
  const DeviceApprovalGate({
    super.key,
    required this.approvalClient,
    required this.identityStore,
    required this.homeBuilder,
  });

  final DeviceApprovalApiClient approvalClient;
  final DeviceIdentityStore identityStore;
  final Widget Function(BuildContext context, String deviceId) homeBuilder;

  @override
  State<DeviceApprovalGate> createState() => _DeviceApprovalGateState();
}

class _DeviceApprovalGateState extends State<DeviceApprovalGate>
    with WidgetsBindingObserver {
  final TextEditingController _teamController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  DeviceRegistration? _registration;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _deviceId;
  String? _errorMessage;

  bool get _isPending => _registration?.approvalStatus == 'N';
  bool get _isApproved => _registration?.approvalStatus == 'Y';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRegistration();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teamController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 관리자가 웹에서 승인한 뒤 앱으로 돌아오는 상황을 위해 재조회합니다.
    if (state == AppLifecycleState.resumed && !_isApproved) {
      _loadRegistration(silent: true);
    }
  }

  Future<void> _loadRegistration({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final deviceId = await widget.identityStore.getOrCreateDeviceId();
      final registration = await widget.approvalClient.fetchRegistration(
        deviceId,
      );
      if (!mounted) return;
      setState(() {
        _deviceId = deviceId;
        _registration = registration;
        _teamController.text = registration?.teamName ?? '';
        _nameController.text = registration?.memberName ?? '';
        _isLoading = false;
        _errorMessage = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '승인 상태를 확인하지 못했어요';
      });
    }
  }

  Future<void> _submitRegistration() async {
    final teamName = _teamController.text.trim();
    final memberName = _nameController.text.trim();
    if (teamName.isEmpty || memberName.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final deviceId =
          _deviceId ?? await widget.identityStore.getOrCreateDeviceId();
      final registration = await widget.approvalClient.submitRegistration(
        deviceId: deviceId,
        teamName: teamName,
        memberName: memberName,
      );
      if (!mounted) return;
      setState(() {
        _deviceId = deviceId;
        _registration = registration;
        _teamController.text = registration.teamName;
        _nameController.text = registration.memberName;
        _isSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = '가입 신청에 실패했어요';
      });
    }
  }

  Future<void> _cancelRegistration() async {
    final deviceId = _deviceId;
    if (deviceId == null || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.approvalClient.cancelRegistration(deviceId);
      if (!mounted) return;
      setState(() {
        _registration = null;
        _teamController.clear();
        _nameController.clear();
        _isSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = '신청 취소에 실패했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isApproved) {
      return widget.homeBuilder(
        context,
        _registration?.deviceId ?? _deviceId ?? '',
      );
    }

    return SplashRegistrationScreen(
      teamController: _teamController,
      nameController: _nameController,
      isLoading: _isLoading,
      isSubmitting: _isSubmitting,
      isPending: _isPending,
      errorMessage: _errorMessage,
      onSubmit: _submitRegistration,
      onCancel: _cancelRegistration,
      onRetry: () => _loadRegistration(),
    );
  }
}

class SplashRegistrationScreen extends StatelessWidget {
  const SplashRegistrationScreen({
    super.key,
    required this.teamController,
    required this.nameController,
    required this.isLoading,
    required this.isSubmitting,
    required this.isPending,
    required this.errorMessage,
    required this.onSubmit,
    required this.onCancel,
    required this.onRetry,
  });

  final TextEditingController teamController;
  final TextEditingController nameController;
  final bool isLoading;
  final bool isSubmitting;
  final bool isPending;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 405),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 31),
                      child: Column(
                        children: [
                          const SizedBox(height: 72),
                          const SplashBrand(),
                          const SizedBox(height: 76),
                          if (isLoading)
                            const SizedBox(
                              height: 214,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFF5A52),
                                ),
                              ),
                            )
                          else ...[
                            SplashTextField(
                              controller: teamController,
                              hintText: '소속 팀 명',
                              enabled: !isPending && !isSubmitting,
                            ),
                            const SizedBox(height: 13),
                            SplashTextField(
                              controller: nameController,
                              hintText: '이름',
                              enabled: !isPending && !isSubmitting,
                            ),
                            const SizedBox(height: 13),
                            SizedBox(
                              width: double.infinity,
                              height: 62,
                              child: FilledButton(
                                onPressed: isPending || isSubmitting
                                    ? null
                                    : onSubmit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: isPending
                                      ? const Color(0xFFC3C3C3)
                                      : const Color(0xFFFF5A52),
                                  disabledBackgroundColor: isPending
                                      ? const Color(0xFFC3C3C3)
                                      : const Color(0xFFFFB5B1),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Text(
                                  isPending ? '신청 완료' : '가입 신청',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 28),
                              TextButton(
                                onPressed: isSubmitting ? null : onCancel,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  disabledForegroundColor: const Color(
                                    0xFFBDBDBD,
                                  ),
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '신청취소',
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                            if (errorMessage != null) ...[
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: onRetry,
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFFF5A52),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SplashBrand extends StatelessWidget {
  const SplashBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/tomato_gold.png',
          width: 150,
          height: 150,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 28),
        const Text(
          '오늘 밥 뭐야?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 32, height: 1, color: Colors.black),
        ),
        const SizedBox(height: 32),
        const Text(
          '금융결제원 생활관 사우들을 위한\n앱으로, 가입 승인이 필요합니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.25, color: Colors.black),
        ),
      ],
    );
  }
}

class SplashTextField extends StatelessWidget {
  const SplashTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.enabled,
  });

  final TextEditingController controller;
  final String hintText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: TextField(
        controller: controller,
        enabled: enabled,
        textInputAction: TextInputAction.next,
        style: TextStyle(
          fontSize: 24,
          color: enabled ? Colors.black : const Color(0xFFCFCFCF),
          height: 1.1,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 24),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          filled: true,
          fillColor: enabled ? Colors.white : const Color(0xFFF4F4F4),
          disabledBorder: _inputBorder(color: const Color(0xFFE0E0E0)),
          enabledBorder: _inputBorder(),
          focusedBorder: _inputBorder(color: const Color(0xFFFF5A52)),
          border: _inputBorder(),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder({
    Color color = const Color(0xFFE1E1E1),
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: 1),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.deviceId,
  });

  final HomeApiClient apiClient;
  final String deviceId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// 홈 화면 상태는 “이번 주 범위 안의 선택 날짜”와 서버에서 받은 홈 데이터를
// 따로 들고 갑니다. 날짜 이동은 현재 주 월~일 안에서만 허용합니다.
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
      // 이미 식단이 있는 날에는 사용자가 실수로 덮어쓰지 않도록 한 번 묻습니다.
      final shouldContinue = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.12),
        builder: (context) {
          return const ExistingMenuDialog();
        },
      );

      if (shouldContinue != true || !mounted) return;
    }

    final didUpload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OcrUploadScreen(deviceId: widget.deviceId),
      ),
    );

    if (didUpload == true && mounted) {
      _loadHome();
    }
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
    return SizedBox(
      height: 63,
      width: double.infinity,
      child: CustomPaint(
        foregroundPainter: const DashedRoundedRectPainter(
          color: Color(0xFF777777),
          strokeWidth: 1.5,
          radius: 18,
          dashLength: 8,
          gapLength: 6,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: WatercolorMealBadge(label: mealLabel),
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
        ),
      ),
    );
  }
}

class WatercolorMealBadge extends StatelessWidget {
  const WatercolorMealBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFB9B5).withValues(alpha: 0.48),
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 5,
            right: 2,
            bottom: 3,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 2.8, sigmaY: 2.8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD0CD).withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 24, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class DashedRoundedRectPainter extends CustomPainter {
  const DashedRoundedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}

class ExistingMenuDialog extends StatelessWidget {
  const ExistingMenuDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 26),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 415),
        padding: const EdgeInsets.fromLTRB(34, 42, 34, 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '이미 등록된 식단표가 있습니다.\n다시 업로드 하시겠습니까?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, height: 1.35, color: Colors.black),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 62,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Color(0xFFE1E1E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('닫기', style: TextStyle(fontSize: 19)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 62,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5A52),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '네! 다시 찍을래요',
                          style: TextStyle(fontSize: 19),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
        'at': DateTime.now().toUtc().toIso8601String(),
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
    // Android 에뮬레이터에서 127.0.0.1은 에뮬레이터 자신을 의미하므로
    // 호스트 맥의 로컬 서버는 10.0.2.2로 접근합니다.
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }
}

// 가입 신청/승인 상태 확인 전용 API 클라이언트입니다.
// 홈 API와 분리해두면 스플래시 게이트 테스트가 쉬워집니다.
class DeviceApprovalApiClient {
  DeviceApprovalApiClient({String? baseUrl})
    : baseUrl = baseUrl ?? HomeApiClient._defaultBaseUrl();

  final String baseUrl;

  Future<DeviceRegistration?> fetchRegistration(String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/device-registrations/$deviceId');
    final response = await _sendJsonRequest(uri, method: 'GET');

    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(response.body, uri: uri);
    }

    return DeviceRegistration.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<DeviceRegistration> submitRegistration({
    required String deviceId,
    required String teamName,
    required String memberName,
  }) async {
    final uri = Uri.parse('$baseUrl/api/device-registrations');
    final response = await _sendJsonRequest(
      uri,
      method: 'POST',
      body: {
        'deviceId': deviceId,
        'teamName': teamName,
        'memberName': memberName,
        'platform': Platform.operatingSystem,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(response.body, uri: uri);
    }

    return DeviceRegistration.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> cancelRegistration(String deviceId) async {
    final uri = Uri.parse('$baseUrl/api/device-registrations/$deviceId');
    final response = await _sendJsonRequest(uri, method: 'DELETE');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(response.body, uri: uri);
    }
  }
}

class DeviceRegistration {
  const DeviceRegistration({
    required this.deviceId,
    required this.teamName,
    required this.memberName,
    required this.approvalStatus,
  });

  final String deviceId;
  final String teamName;
  final String memberName;
  final String approvalStatus;

  factory DeviceRegistration.fromJson(Map<String, dynamic> json) {
    return DeviceRegistration(
      deviceId: json['deviceId'] as String? ?? '',
      teamName: json['teamName'] as String? ?? '',
      memberName: json['memberName'] as String? ?? '',
      approvalStatus:
          json['approvalStatus'] as String? ??
          ((json['approved'] as bool? ?? false) ? 'Y' : 'N'),
    );
  }
}

class DeviceIdentityStore {
  static const _deviceIdKey = 'today_bob_device_id';

  Future<String> getOrCreateDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final savedDeviceId = preferences.getString(_deviceIdKey);
    if (savedDeviceId != null && savedDeviceId.isNotEmpty) {
      return savedDeviceId;
    }

    final deviceId = _createDeviceId();
    await preferences.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  String _createDeviceId() {
    // 기기 고유 식별자를 직접 읽지 않고, 앱 설치 단위의 UUID를 만들어 저장합니다.
    // 사용자가 앱을 삭제하면 새 기기로 다시 가입 신청하는 흐름이 됩니다.
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }
}

class _ApiResponse {
  const _ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

Future<_ApiResponse> _sendJsonRequest(
  Uri uri, {
  required String method,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 3);

  try {
    final request = await client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(const Duration(seconds: 5));
    return _ApiResponse(
      statusCode: response.statusCode,
      body: await response.transform(utf8.decoder).join(),
    );
  } finally {
    client.close(force: true);
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

String _mealLabel(String type) => type == 'breakfast' ? '아침' : '저녁';

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
