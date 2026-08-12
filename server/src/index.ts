import { neon } from '@neondatabase/serverless';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';

dotenv.config();

type MealType = 'breakfast' | 'dinner';
type SqlClient = ReturnType<typeof neon>;
type QueryRow = Record<string, unknown>;

type MenuRow = {
  date: string;
  breakfastMenu: string;
  dinnerMenu: string;
};

type MessageRow = {
  id: string;
  text: string;
};

type OperatingHoursRow = {
  weekday: number;
  breakfastStart: string;
  breakfastEnd: string;
  dinnerStart: string;
  dinnerEnd: string;
};

type WeeklyMenuUploadDay = {
  weekday?: unknown;
  breakfast?: unknown;
  dinner?: unknown;
};

const seedMenuRows: MenuRow[] = [
  {
    date: '2026-08-11',
    breakfastMenu:
      '길거리토스트, 우유/요구르트, 버섯된장국, 연두부/양념장, 샐러드/과일, 배추김치.흰밥',
    dinnerMenu: '제육볶음, 미역국, 계란말이, 샐러드, 배추김치, 흰밥',
  },
  {
    date: '2026-08-12',
    breakfastMenu:
      '길거리토스트, 우유/요구르트, 버섯된장국, 연두부/양념장, 샐러드/과일, 배추김치.흰밥',
    dinnerMenu: '제육볶음, 미역국, 계란말이, 샐러드, 배추김치, 흰밥',
  },
];

const seedMessageRows: MessageRow[] = [
  { id: '1', text: '제가 가장 좋아하는 메뉴는 계란말이 입니다.' },
  { id: '2', text: '아 이런 오늘은 다이어트하려고 했는데' },
  {
    id: '3',
    text: '샐러드를 먼저 먹어야 혈당 스파이크를 방지할 수 있습니다.',
  },
  { id: '4', text: '제 최애 아침메뉴는 길거리토스트입니다.' },
];

const seedOperatingHoursRows: OperatingHoursRow[] = [
  {
    weekday: 1,
    breakfastStart: '07:00',
    breakfastEnd: '09:00',
    dinnerStart: '18:30',
    dinnerEnd: '20:30',
  },
  {
    weekday: 2,
    breakfastStart: '07:00',
    breakfastEnd: '09:00',
    dinnerStart: '18:30',
    dinnerEnd: '20:30',
  },
  {
    weekday: 3,
    breakfastStart: '07:00',
    breakfastEnd: '09:00',
    dinnerStart: '17:30',
    dinnerEnd: '20:00',
  },
  {
    weekday: 4,
    breakfastStart: '07:00',
    breakfastEnd: '09:00',
    dinnerStart: '18:30',
    dinnerEnd: '20:30',
  },
  {
    weekday: 5,
    breakfastStart: '07:00',
    breakfastEnd: '09:00',
    dinnerStart: '17:30',
    dinnerEnd: '20:00',
  },
  {
    weekday: 6,
    breakfastStart: '08:00',
    breakfastEnd: '10:00',
    dinnerStart: '18:00',
    dinnerEnd: '20:00',
  },
  {
    weekday: 7,
    breakfastStart: '08:00',
    breakfastEnd: '10:00',
    dinnerStart: '18:00',
    dinnerEnd: '20:00',
  },
];

const memoryMenuRows = [...seedMenuRows];
const memoryMessageRows = [...seedMessageRows];
const memoryOperatingHoursRows = [...seedOperatingHoursRows];

let sqlClient: SqlClient | null | undefined;
let databaseReady = false;
let databaseReadyPromise: Promise<void> | null = null;

export const app = express();
const port = Number(process.env.PORT ?? 3000);

app.use(cors());
app.use(express.json());

app.get('/health', async (_request, response) => {
  response.json({
    status: 'ok',
    storage: (await hasDatabase()) ? 'postgres' : 'memory',
  });
});

app.get('/api/home', async (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const mealType = await getCurrentMealType(
    date.value,
    parseAtQuery(request.query.at),
  );
  const menu = await findMenu(date.value, mealType);
  const operatingHours = await findOperatingHours(date.value, mealType);

  response.json({
    date: date.value,
    weekday: getWeekday(date.value),
    menu,
    message: (await getRandomMessage()).text,
    operatingHours,
  });
});

app.get('/api/menus', async (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const row = await getMenuRow(date.value);

  response.json({
    date: date.value,
    breakfast: splitMenu(row?.breakfastMenu ?? ''),
    dinner: splitMenu(row?.dinnerMenu ?? ''),
  });
});

app.get('/api/menus/current', async (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const mealType = await getCurrentMealType(
    date.value,
    parseAtQuery(request.query.at),
  );
  response.json(await findMenu(date.value, mealType));
});

app.post('/api/menus/week', async (request, response) => {
  const startDate = parseDateQuery(request.body?.startDate);
  if (!startDate.ok) {
    response
      .status(400)
      .json({ message: 'startDate is required in YYYY-MM-DD format' });
    return;
  }

  if (getWeekday(startDate.value) !== 1) {
    response.status(400).json({ message: 'startDate must be a Monday' });
    return;
  }

  const days = request.body?.days;
  if (!Array.isArray(days) || days.length !== 7) {
    response
      .status(400)
      .json({ message: 'days must contain exactly 7 menu rows' });
    return;
  }

  const menus = days.map((day: WeeklyMenuUploadDay, index: number) => {
    return {
      date: addDays(startDate.value, index),
      breakfastMenu: joinMenu(readMenuItems(day.breakfast)),
      dinnerMenu: joinMenu(readMenuItems(day.dinner)),
    };
  });

  await Promise.all(menus.map(upsertMenu));

  response.status(201).json({
    startDate: startDate.value,
    endDate: addDays(startDate.value, 6),
    inserted: menus.length,
    menus: menus.map((menu) => ({
      date: menu.date,
      breakfast: splitMenu(menu.breakfastMenu),
      dinner: splitMenu(menu.dinnerMenu),
    })),
  });
});

app.get('/api/messages/random', async (_request, response) => {
  response.json(await getRandomMessage());
});

app.get('/api/operating-hours/current', async (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const mealType = await getCurrentMealType(
    date.value,
    parseAtQuery(request.query.at),
  );
  response.json(await findOperatingHours(date.value, mealType));
});

app.use(
  (
    error: unknown,
    _request: express.Request,
    response: express.Response,
    _next: express.NextFunction,
  ) => {
    console.error(error);
    response.status(500).json({ message: 'Internal server error' });
  },
);

if (process.env.VERCEL !== '1') {
  app.listen(port, () => {
    console.log(`today-bob server listening on http://localhost:${port}`);
  });
}

export default app;

async function hasDatabase(): Promise<boolean> {
  return (await database()) != null;
}

async function database(): Promise<SqlClient | null> {
  if (!process.env.DATABASE_URL) return null;
  sqlClient ??= neon(process.env.DATABASE_URL);
  await ensureDatabase(sqlClient);
  return sqlClient;
}

async function ensureDatabase(client: SqlClient): Promise<void> {
  if (databaseReady) return;

  databaseReadyPromise ??= createSchema(client)
    .then(() => {
      databaseReady = true;
    })
    .catch((error: unknown) => {
      databaseReadyPromise = null;
      throw error;
    });

  await databaseReadyPromise;
}

async function createSchema(client: SqlClient): Promise<void> {
  await client`
    create table if not exists menus (
      date date primary key,
      breakfast_menu text not null,
      dinner_menu text not null
    )
  `;

  await client`
    create table if not exists messages (
      id bigserial primary key,
      text text not null
    )
  `;

  await client`
    create table if not exists operating_hours (
      weekday smallint primary key,
      breakfast_start time not null,
      breakfast_end time not null,
      dinner_start time not null,
      dinner_end time not null
    )
  `;

  await Promise.all(seedMenuRows.map((row) => insertSeedMenu(client, row)));
  await Promise.all(
    seedMessageRows.map((row) => insertSeedMessage(client, row.text)),
  );
  await Promise.all(
    seedOperatingHoursRows.map((row) => upsertOperatingHours(client, row)),
  );
}

async function insertSeedMenu(
  client: SqlClient,
  row: MenuRow,
): Promise<void> {
  await client`
    insert into menus (date, breakfast_menu, dinner_menu)
    values (${row.date}, ${row.breakfastMenu}, ${row.dinnerMenu})
    on conflict (date) do nothing
  `;
}

async function insertSeedMessage(
  client: SqlClient,
  text: string,
): Promise<void> {
  await client`
    insert into messages (text)
    select ${text}
    where not exists (select 1 from messages where text = ${text})
  `;
}

async function upsertOperatingHours(
  client: SqlClient,
  row: OperatingHoursRow,
): Promise<void> {
  await client`
    insert into operating_hours (
      weekday,
      breakfast_start,
      breakfast_end,
      dinner_start,
      dinner_end
    )
    values (
      ${row.weekday},
      ${row.breakfastStart},
      ${row.breakfastEnd},
      ${row.dinnerStart},
      ${row.dinnerEnd}
    )
    on conflict (weekday) do update set
      breakfast_start = excluded.breakfast_start,
      breakfast_end = excluded.breakfast_end,
      dinner_start = excluded.dinner_start,
      dinner_end = excluded.dinner_end
  `;
}

async function getMenuRow(date: string): Promise<MenuRow | undefined> {
  const client = await database();
  if (!client) {
    return memoryMenuRows.find((menuRow) => menuRow.date === date);
  }

  const rows = (await client`
    select
      date::text as date,
      breakfast_menu as "breakfastMenu",
      dinner_menu as "dinnerMenu"
    from menus
    where date = ${date}
    limit 1
  `) as QueryRow[];

  return rows[0] ? menuRowFromQuery(rows[0]) : undefined;
}

async function upsertMenu(menu: MenuRow): Promise<void> {
  const client = await database();
  if (!client) {
    const index = memoryMenuRows.findIndex((row) => row.date === menu.date);
    if (index >= 0) {
      memoryMenuRows[index] = menu;
      return;
    }

    memoryMenuRows.push(menu);
    return;
  }

  await client`
    insert into menus (date, breakfast_menu, dinner_menu)
    values (${menu.date}, ${menu.breakfastMenu}, ${menu.dinnerMenu})
    on conflict (date) do update set
      breakfast_menu = excluded.breakfast_menu,
      dinner_menu = excluded.dinner_menu
  `;
}

async function getRandomMessage(): Promise<MessageRow> {
  const client = await database();
  if (!client) {
    return (
      memoryMessageRows[
        Math.floor(Math.random() * memoryMessageRows.length)
      ] ?? memoryMessageRows[0]
    );
  }

  const rows = (await client`
    select id::text, text
    from messages
    order by random()
    limit 1
  `) as QueryRow[];

  return rows[0] ? messageRowFromQuery(rows[0]) : seedMessageRows[0];
}

async function getOperatingHoursRow(
  weekday: number,
): Promise<OperatingHoursRow | undefined> {
  const client = await database();
  if (!client) {
    return memoryOperatingHoursRows.find(
      (hoursRow) => hoursRow.weekday === weekday,
    );
  }

  const rows = (await client`
    select
      weekday,
      to_char(breakfast_start, 'HH24:MI') as "breakfastStart",
      to_char(breakfast_end, 'HH24:MI') as "breakfastEnd",
      to_char(dinner_start, 'HH24:MI') as "dinnerStart",
      to_char(dinner_end, 'HH24:MI') as "dinnerEnd"
    from operating_hours
    where weekday = ${weekday}
    limit 1
  `) as QueryRow[];

  return rows[0] ? operatingHoursRowFromQuery(rows[0]) : undefined;
}

function parseDateQuery(
  value: unknown,
): { ok: true; value: string } | { ok: false; message: string } {
  const date = String(value ?? '');

  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return {
      ok: false,
      message: 'date query is required in YYYY-MM-DD format',
    };
  }

  return { ok: true, value: date };
}

function parseAtQuery(value: unknown): Date {
  const rawValue = String(value ?? '').trim();
  if (!rawValue) return new Date();

  const hasTimeZone = /(?:z|[+-]\d{2}:?\d{2})$/i.test(rawValue);
  const date = new Date(hasTimeZone ? rawValue : `${rawValue}+09:00`);
  return Number.isNaN(date.getTime()) ? new Date() : date;
}

function readMenuItems(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item).trim()).filter(Boolean);
}

function joinMenu(items: string[]): string {
  return items.join(', ');
}

function addDays(date: string, days: number): string {
  const [year, month, day] = date.split('-').map(Number);
  const nextDate = new Date(Date.UTC(year, month - 1, day + days));
  const nextMonth = String(nextDate.getUTCMonth() + 1).padStart(2, '0');
  const nextDay = String(nextDate.getUTCDate()).padStart(2, '0');
  return `${nextDate.getUTCFullYear()}-${nextMonth}-${nextDay}`;
}

async function findMenu(date: string, type: MealType) {
  const row = await getMenuRow(date);
  const items = splitMenu(
    type === 'breakfast' ? row?.breakfastMenu : row?.dinnerMenu,
  );

  return {
    date,
    type,
    label: mealLabel(type),
    items,
    hasMenu: items.length > 0,
  };
}

async function findOperatingHours(date: string, type: MealType) {
  const weekday = getWeekday(date);
  const row = await getOperatingHoursRow(weekday);

  if (!row) {
    return {
      date,
      weekday,
      type,
      label: '-',
      start: null,
      end: null,
    };
  }

  const start = type === 'breakfast' ? row.breakfastStart : row.dinnerStart;
  const end = type === 'breakfast' ? row.breakfastEnd : row.dinnerEnd;

  return {
    date,
    weekday,
    type,
    label: `${start} ~ ${end}`,
    start,
    end,
  };
}

async function getCurrentMealType(date: string, at: Date): Promise<MealType> {
  const hours = await findOperatingHours(date, 'breakfast');
  const currentMinutes = getKoreanTimeMinutes(at);
  const breakfastEndMinutes = parseTimeToMinutes(hours.end ?? '09:00');

  return currentMinutes <= breakfastEndMinutes ? 'breakfast' : 'dinner';
}

function splitMenu(value = ''): string[] {
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function mealLabel(type: MealType): string {
  return type === 'breakfast' ? '아침' : '저녁';
}

function getWeekday(date: string): number {
  const [year, month, day] = date.split('-').map(Number);
  const jsDay = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return jsDay === 0 ? 7 : jsDay;
}

function getKoreanTimeMinutes(date: Date): number {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Seoul',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(date);
  const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? '0');
  const minute = Number(
    parts.find((part) => part.type === 'minute')?.value ?? '0',
  );
  return hour * 60 + minute;
}

function parseTimeToMinutes(value: string): number {
  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
}

function menuRowFromQuery(row: QueryRow): MenuRow {
  return {
    date: String(row.date),
    breakfastMenu: String(row.breakfastMenu ?? ''),
    dinnerMenu: String(row.dinnerMenu ?? ''),
  };
}

function messageRowFromQuery(row: QueryRow): MessageRow {
  return {
    id: String(row.id),
    text: String(row.text ?? ''),
  };
}

function operatingHoursRowFromQuery(row: QueryRow): OperatingHoursRow {
  return {
    weekday: Number(row.weekday),
    breakfastStart: String(row.breakfastStart),
    breakfastEnd: String(row.breakfastEnd),
    dinnerStart: String(row.dinnerStart),
    dinnerEnd: String(row.dinnerEnd),
  };
}
