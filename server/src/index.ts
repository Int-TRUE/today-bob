import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';

dotenv.config();

type MealType = 'breakfast' | 'dinner';

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

const menuRows: MenuRow[] = [
  {
    date: '2026-08-11',
    breakfastMenu: '길거리토스트, 우유/요구르트, 버섯된장국, 연두부/양념장, 샐러드/과일, 배추김치.흰밥',
    dinnerMenu: '제육볶음, 미역국, 계란말이, 샐러드, 배추김치, 흰밥',
  },
  {
    date: '2026-08-12',
    breakfastMenu: '길거리토스트, 우유/요구르트, 버섯된장국, 연두부/양념장, 샐러드/과일, 배추김치.흰밥',
    dinnerMenu: '제육볶음, 미역국, 계란말이, 샐러드, 배추김치, 흰밥',
  },
];

const messageRows: MessageRow[] = [
  { id: '1', text: '제가 가장 좋아하는 메뉴는 계란말이 입니다.' },
  { id: '2', text: '오늘도 든든하게 먹고 좋은 하루 보내세요.' },
  { id: '3', text: '김치가 맛있는 날은 밥이 더 빨리 사라집니다.' },
];

const operatingHoursRows: OperatingHoursRow[] = [
  { weekday: 1, breakfastStart: '07:30', breakfastEnd: '08:30', dinnerStart: '18:00', dinnerEnd: '19:00' },
  { weekday: 2, breakfastStart: '07:30', breakfastEnd: '08:30', dinnerStart: '18:00', dinnerEnd: '19:00' },
  { weekday: 3, breakfastStart: '07:30', breakfastEnd: '08:30', dinnerStart: '18:00', dinnerEnd: '19:00' },
  { weekday: 4, breakfastStart: '07:30', breakfastEnd: '08:30', dinnerStart: '18:00', dinnerEnd: '19:00' },
  { weekday: 5, breakfastStart: '07:30', breakfastEnd: '08:30', dinnerStart: '18:00', dinnerEnd: '19:00' },
  { weekday: 6, breakfastStart: '08:00', breakfastEnd: '09:00', dinnerStart: '17:30', dinnerEnd: '18:30' },
  { weekday: 7, breakfastStart: '08:00', breakfastEnd: '09:00', dinnerStart: '17:30', dinnerEnd: '18:30' },
];

const app = express();
const port = Number(process.env.PORT ?? 3000);

app.use(cors());
app.use(express.json());

app.get('/health', (_request, response) => {
  response.json({ status: 'ok' });
});

app.get('/api/home', (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const mealType = getCurrentMealType(date.value, parseAtQuery(request.query.at));
  const menu = findMenu(date.value, mealType);
  const operatingHours = findOperatingHours(date.value, mealType);

  response.json({
    date: date.value,
    weekday: getWeekday(date.value),
    menu,
    message: getRandomMessage().text,
    operatingHours,
  });
});

app.get('/api/menus', (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const row = menuRows.find((menuRow) => menuRow.date === date.value);

  response.json({
    date: date.value,
    breakfast: splitMenu(row?.breakfastMenu ?? ''),
    dinner: splitMenu(row?.dinnerMenu ?? ''),
  });
});

app.get('/api/menus/current', (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const mealType = getCurrentMealType(date.value, parseAtQuery(request.query.at));
  response.json(findMenu(date.value, mealType));
});

app.get('/api/messages/random', (_request, response) => {
  response.json(getRandomMessage());
});

app.get('/api/operating-hours/current', (request, response) => {
  const date = parseDateQuery(request.query.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  const mealType = getCurrentMealType(date.value, parseAtQuery(request.query.at));
  response.json(findOperatingHours(date.value, mealType));
});

app.listen(port, () => {
  console.log(`today-bob server listening on http://localhost:${port}`);
});

function parseDateQuery(value: unknown): { ok: true; value: string } | { ok: false; message: string } {
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
  const date = new Date(String(value ?? ''));
  return Number.isNaN(date.getTime()) ? new Date() : date;
}

function findMenu(date: string, type: MealType) {
  const row = menuRows.find((menuRow) => menuRow.date === date);
  const items = splitMenu(type === 'breakfast' ? row?.breakfastMenu : row?.dinnerMenu);

  return {
    date,
    type,
    label: mealLabel(type),
    items,
    hasMenu: items.length > 0,
  };
}

function findOperatingHours(date: string, type: MealType) {
  const weekday = getWeekday(date);
  const row = operatingHoursRows.find((hoursRow) => hoursRow.weekday === weekday);

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

function getCurrentMealType(date: string, at: Date): MealType {
  const hours = findOperatingHours(date, 'breakfast');
  const currentMinutes = getKoreanTimeMinutes(at);
  const breakfastEndMinutes = parseTimeToMinutes(hours.end ?? '08:30');

  return currentMinutes <= breakfastEndMinutes ? 'breakfast' : 'dinner';
}

function getRandomMessage(): MessageRow {
  return messageRows[Math.floor(Math.random() * messageRows.length)] ?? messageRows[0];
}

function splitMenu(value = ''): string[] {
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function mealLabel(type: MealType): string {
  return type === 'breakfast' ? '조식' : '저녁';
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
  const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? '0');
  return hour * 60 + minute;
}

function parseTimeToMinutes(value: string): number {
  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
}
