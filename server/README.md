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
- `GET /api/menus/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/messages/random`
- `GET /api/operating-hours/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/home?date=YYYY-MM-DD&at=ISO_DATE`

`/api/home` is the app-friendly aggregate endpoint for the first home-screen load.

## DB Draft

The server currently uses seed rows with the same shape as the planned DB.

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
