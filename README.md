# 오늘 밥 뭐야?

금융결제원 생활관 사우들을 위한 식단 확인 앱입니다.  
오늘 날짜와 현재 시간에 맞춰 아침 또는 저녁 식단을 보여주고, 위젯과 관리자 페이지까지 함께 제공해 식단 등록과 수정 흐름을 간단하게 만들었습니다.

## 스크린샷

| 홈 화면 | 가입 승인 |
| --- | --- |
| ![홈 화면](docs/screenshots/home.svg) | ![가입 승인](docs/screenshots/approval.svg) |

| OCR 식단 등록 | 관리자 페이지 |
| --- | --- |
| ![OCR 식단 등록](docs/screenshots/ocr-result.svg) | ![관리자 페이지](docs/screenshots/admin.svg) |

## 주요 기능

- **오늘 식단 확인**: 날짜와 요일을 기준으로 아침/저녁 식단을 조회합니다.
- **주간 날짜 이동**: 현재 주의 월요일부터 일요일까지 이전/다음 날짜로 이동할 수 있습니다.
- **운영 시간 표시**: 요일별 아침/저녁 운영 시간을 서버에서 불러와 함께 보여줍니다.
- **식단 없음 안내**: 해당 시간대 식단이 없으면 별도 안내 문구를 표시합니다.
- **흐르는 한마디**: DB에 저장된 문구 중 하나를 랜덤으로 불러와 홈 화면에 노출합니다.
- **OCR 식단 등록**: 식단표 사진을 촬영해 7일 x 2식 영역으로 나누고, Google ML Kit OCR로 메뉴를 추출합니다.
- **직접 편집 후 업로드**: OCR 결과 화면에서 메뉴를 직접 수정한 뒤 서버에 주간 식단을 저장합니다.
- **홈 화면 위젯**: iOS/Android 위젯에서 현재 시간대 메뉴와 운영 시간을 빠르게 확인합니다.
- **기기 승인 기반 접근**: 승인된 기기만 앱의 식단 업로드와 관리자 기능을 사용할 수 있습니다.
- **관리자 웹페이지**: 식단, 흐르는 문구, 운영 시간, 가입 기기를 웹에서 CRUD할 수 있습니다.

## 사용자 흐름

1. 앱을 처음 실행하면 팀명과 이름을 입력해 가입 신청을 합니다.
2. 신청된 기기는 서버 DB에 승인 `N` 상태로 저장됩니다.
3. 관리자가 기기를 승인하면 앱 홈 화면에 진입할 수 있습니다.
4. 홈 화면에서는 현재 날짜와 시간에 맞는 식단, 운영 시간, 랜덤 문구를 확인합니다.
5. 식단 업로드 버튼을 누르면 카메라/OCR 화면으로 이동합니다.
6. 식단표를 촬영하면 OCR 결과를 표 형태로 확인하고 직접 수정할 수 있습니다.
7. 저장 시 승인된 기기 ID를 함께 보내 서버의 주간 식단 DB에 반영합니다.

## 관리자 페이지

관리자 페이지는 배포된 서버에서 제공됩니다.

- URL: `<DEPLOYED_SERVER_URL>/admin`
- 최초 1회 관리자 기기 ID 입력 후 90일 동안 HttpOnly 쿠키로 인증이 유지됩니다.
- Vercel `ADMIN_DEVICE_ID` 환경변수로 관리자 기기를 고정할 수 있습니다.

관리 가능한 데이터:

- `menus`: 날짜별 아침/저녁 식단
- `messages`: 홈 화면에 흐르는 랜덤 문구
- `operating_hours`: 요일별 아침/저녁 운영 시간
- `device_registrations`: 가입 신청 기기와 승인 상태

## 위젯

앱은 iOS와 Android 홈 화면 위젯을 제공합니다.

- 현재 날짜와 시간대에 맞는 메뉴를 최대 6줄까지 표시합니다.
- 운영 시간이 있으면 `07:00~09:00` 형태로 하단에 표시합니다.
- 식단이 없거나 서버 호출에 실패하면 `등록된 식단이 없어요`를 표시합니다.

## 기술 구성

```text
today-bob
├── app/      Flutter mobile app
└── server/   Express API server
```

### App

- Flutter
- iOS WidgetKit extension
- Android AppWidgetProvider
- Google ML Kit Text Recognition
- Image Picker
- Shared Preferences

### Server

- Node.js
- Express
- Neon Postgres
- Vercel deployment

## 서버 API 개요

앱에서 사용하는 주요 API:

- `GET /api/home?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/menus?date=YYYY-MM-DD`
- `GET /api/menus/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/messages/random`
- `GET /api/operating-hours/current?date=YYYY-MM-DD&at=ISO_DATE`
- `POST /api/device-registrations`
- `GET /api/device-registrations/:deviceId`
- `DELETE /api/device-registrations/:deviceId`
- `POST /api/menus/week`

관리자 API:

- `POST /api/admin/session`
- `DELETE /api/admin/session`
- `GET /api/admin/snapshot`
- `POST /api/admin/menus`
- `DELETE /api/admin/menus/:date`
- `POST /api/admin/messages`
- `PUT /api/admin/messages/:id`
- `DELETE /api/admin/messages/:id`
- `POST /api/admin/operating-hours`
- `PUT /api/admin/operating-hours/:weekday`
- `DELETE /api/admin/operating-hours/:weekday`
- `POST /api/admin/device-registrations`
- `PUT /api/admin/device-registrations/:deviceId`
- `DELETE /api/admin/device-registrations/:deviceId`

## 데이터 모델

서버는 `DATABASE_URL`이 있으면 Postgres를 사용하고, 없으면 개발용 메모리 데이터를 사용합니다.

주요 테이블:

- `menus`: `date`, `breakfast_menu`, `dinner_menu`
- `messages`: `id`, `text`
- `operating_hours`: `weekday`, `breakfast_start`, `breakfast_end`, `dinner_start`, `dinner_end`
- `device_registrations`: `device_id`, `team_name`, `member_name`, `approved`, `platform`, `created_at`, `updated_at`

## 실행 방법

### Flutter 앱

```bash
cd app
flutter pub get
flutter run
```

배포 서버를 명시하려면:

```bash
flutter run --dart-define=API_BASE_URL=<DEPLOYED_SERVER_URL>
```

### 서버

```bash
cd server
npm install
npm run dev
```

환경변수:

```bash
PORT=3000
DATABASE_URL=postgres://user:password@host/database?sslmode=require
ADMIN_DEVICE_ID=approved-device-id
```

## 현재 배포

- API 서버: 배포 URL은 공개 README에서 생략합니다.
- 관리자 페이지: `<DEPLOYED_SERVER_URL>/admin`
