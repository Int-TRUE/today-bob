# today-bob

금융결제원 생활관 식단 공유 앱.

## Structure

- `app/`: Flutter mobile app
- `server/`: API server

## App

```bash
cd app
flutter run
```

## Server

```bash
cd server
npm install
npm run dev
```

The first server scaffold exposes:

- `GET /health`
- `GET /api/menus?date=YYYY-MM-DD`
