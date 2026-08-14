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
ADMIN_DEVICE_ID=approved-device-id
```

If `DATABASE_URL` is present, the server creates and uses Postgres tables.
Without it, the server falls back to local seed data for development.
`ADMIN_DEVICE_ID` is optional. When present, only that approved registered
device can use the admin page. When absent, admin access is allowed only when
there is exactly one approved registered device and the request uses that ID.

## Endpoints

- `GET /health`
- `GET /api/menus?date=YYYY-MM-DD`
- `GET /api/menus/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/messages/random`
- `GET /api/operating-hours/current?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/home?date=YYYY-MM-DD&at=ISO_DATE`
- `GET /api/device-registrations/:deviceId`
- `POST /api/device-registrations`
- `DELETE /api/device-registrations/:deviceId`
- `POST /api/menus/week`
- `GET /admin`
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

`/api/home` is the app-friendly aggregate endpoint for the first home-screen load.
`POST /api/menus/week` requires an approved `x-device-id` request header.
Admin API endpoints require an approved `x-admin-device-id` request header.
The admin page stores a 90-day HttpOnly session cookie through
`POST /api/admin/session`, so the device ID only needs to be entered once per
browser unless the session is cleared.

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

create table device_registrations (
  device_id text primary key,
  team_name text not null,
  member_name text not null,
  approved char(1) not null default 'N',
  platform text not null default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Approve a registered device manually:

```sql
select device_id, team_name, member_name, approved, platform, created_at
from device_registrations
order by created_at desc;

update device_registrations
set approved = 'Y', updated_at = now()
where device_id = 'DEVICE_ID';
```

Menu strings are split by comma before being returned to the app.

Default operating hours:

- Monday, Tuesday, Thursday: breakfast `07:00 ~ 09:00`, dinner `18:30 ~ 20:30`
- Wednesday, Friday: breakfast `07:00 ~ 09:00`, dinner `17:30 ~ 20:00`
- Saturday, Sunday: breakfast `08:00 ~ 10:00`, dinner `18:00 ~ 20:00`
