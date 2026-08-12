# today-bob server

Simple API server for the dormitory meal app.

## Run

```bash
npm install
npm run dev
```

## Environment

Copy `.env.example` to `.env` when a database is selected.

```bash
PORT=3000
DATABASE_URL=postgres://user:password@host/database?sslmode=require
```

If `DATABASE_URL` is present, the server creates and uses Postgres tables.
Without it, the server falls back to local seed data for development.

## Endpoints

- `GET /health`
- `GET /api/menus?date=YYYY-MM-DD`
- `GET /api/menus/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/messages/random`
- `GET /api/operating-hours/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/home?date=YYYY-MM-DD&at=ISO_DATE`
- `POST /api/menus/week`

`/api/home` is the app-friendly aggregate endpoint for the first home-screen load.

## DB Tables

The server creates these tables automatically on first request when `DATABASE_URL`
is configured.

```sql
create table menus (
  date date primary key,
  breakfast_menu text not null,
  dinner_menu text not null
);

create table messages (
  id bigserial primary key,
  text text not null
);

create table operating_hours (
  weekday smallint primary key,
  breakfast_start time not null,
  breakfast_end time not null,
  dinner_start time not null,
  dinner_end time not null
);
```

Menu strings are split by comma before being returned to the app.

Default operating hours:

- Monday, Tuesday, Thursday: breakfast `07:00 ~ 09:00`, dinner `18:30 ~ 20:30`
- Wednesday, Friday: breakfast `07:00 ~ 09:00`, dinner `17:30 ~ 20:00`
- Saturday, Sunday: breakfast `08:00 ~ 10:00`, dinner `18:00 ~ 20:00`
