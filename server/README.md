# today-bob server

Simple API server for the dormitory meal app.

## Run

```bash
npm install
npm run dev
```

## Environment

Copy `.env.example` to `.env` when a database is selected.

## Endpoints

- `GET /health`
- `GET /api/menus?date=YYYY-MM-DD`

The menu endpoint currently returns an empty list. Once the Figma screens and meal data flow are confirmed, this folder can grow into the real API and DB layer.
