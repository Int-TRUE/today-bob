import 'package:flutter_test/flutter_test.dart';

import 'package:today_bob_app/main.dart';

void main() {
  testWidgets('renders app shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      TodayBobApp(
        apiClient: FakeHomeApiClient(),
        deviceApprovalClient: FakeApprovedDeviceApprovalClient(),
        deviceIdentityStore: FakeDeviceIdentityStore(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('월'), findsWidgets);
    expect(find.text('길거리토스트'), findsOneWidget);
    expect(find.text('이번주 식단 업로드'), findsOneWidget);
  });

  testWidgets('renders registration form for unknown device', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      TodayBobApp(
        apiClient: FakeHomeApiClient(),
        deviceApprovalClient: FakeUnknownDeviceApprovalClient(),
        deviceIdentityStore: FakeDeviceIdentityStore(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('소속 팀 명'), findsOneWidget);
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('가입 신청'), findsOneWidget);
  });

  testWidgets('renders disabled pending registration form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      TodayBobApp(
        apiClient: FakeHomeApiClient(),
        deviceApprovalClient: FakePendingDeviceApprovalClient(),
        deviceIdentityStore: FakeDeviceIdentityStore(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('IT운영팀'), findsOneWidget);
    expect(find.text('정수진'), findsOneWidget);
    expect(find.text('신청 완료'), findsOneWidget);
    expect(find.text('신청취소'), findsOneWidget);
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

class FakeApprovedDeviceApprovalClient implements DeviceApprovalApiClient {
  @override
  String get baseUrl => 'http://example.test';

  @override
  Future<void> cancelRegistration(String deviceId) async {}

  @override
  Future<DeviceRegistration?> fetchRegistration(String deviceId) async {
    return DeviceRegistration(
      deviceId: deviceId,
      teamName: '생활관팀',
      memberName: '테스터',
      approvalStatus: 'Y',
    );
  }

  @override
  Future<DeviceRegistration> submitRegistration({
    required String deviceId,
    required String teamName,
    required String memberName,
  }) async {
    return DeviceRegistration(
      deviceId: deviceId,
      teamName: teamName,
      memberName: memberName,
      approvalStatus: 'N',
    );
  }
}

class FakeUnknownDeviceApprovalClient extends FakeApprovedDeviceApprovalClient {
  @override
  Future<DeviceRegistration?> fetchRegistration(String deviceId) async => null;
}

class FakePendingDeviceApprovalClient extends FakeApprovedDeviceApprovalClient {
  @override
  Future<DeviceRegistration?> fetchRegistration(String deviceId) async {
    return DeviceRegistration(
      deviceId: deviceId,
      teamName: 'IT운영팀',
      memberName: '정수진',
      approvalStatus: 'N',
    );
  }
}

class FakeDeviceIdentityStore implements DeviceIdentityStore {
  @override
  Future<String> getOrCreateDeviceId() async => 'test-device-id';
}
