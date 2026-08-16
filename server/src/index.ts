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

type DeviceRegistrationRow = {
  deviceId: string;
  teamName: string;
  memberName: string;
  approved: 'Y' | 'N';
  platform: string;
  createdAt: string;
  updatedAt: string;
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
const memoryDeviceRegistrationRows: DeviceRegistrationRow[] = [];
const adminCookieName = 'today_bob_admin_device_id';
const adminCookieMaxAgeSeconds = 60 * 60 * 24 * 90;

let sqlClient: SqlClient | null | undefined;
let databaseReady = false;
let databaseReadyPromise: Promise<void> | null = null;

export const app = express();
const port = Number(process.env.PORT ?? 3000);

app.use(cors());
app.use(express.json());

// 앱에서 자주 쓰는 공개 API들입니다.
// /api/home은 홈 화면 첫 로드에 필요한 식단/랜덤 문구/운영 시간을 한 번에 돌려줍니다.
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
  // 주간 식단 업로드는 승인된 앱 기기에서만 허용합니다.
  // deviceId는 앱 설치 시 생성되어 x-device-id 헤더로 전달됩니다.
  const approvedDevice = await isApprovedDevice(
    parseRequiredText(request.header('x-device-id')),
  );
  if (!approvedDevice) {
    response.status(403).json({ message: 'Device approval is required' });
    return;
  }

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

app.get('/api/device-registrations/:deviceId', async (request, response) => {
  const deviceId = parseRequiredText(request.params.deviceId);
  if (!deviceId) {
    response.status(400).json({ message: 'deviceId is required' });
    return;
  }

  const registration = await getDeviceRegistration(deviceId);
  if (!registration) {
    response.status(404).json({ message: 'Device registration not found' });
    return;
  }

  response.json(deviceRegistrationResponse(registration));
});

app.post('/api/device-registrations', async (request, response) => {
  const deviceId = parseRequiredText(request.body?.deviceId);
  const teamName = parseRequiredText(request.body?.teamName);
  const memberName = parseRequiredText(request.body?.memberName);
  const platform = parseRequiredText(request.body?.platform) ?? 'unknown';

  if (!deviceId || !teamName || !memberName) {
    response.status(400).json({
      message: 'deviceId, teamName, and memberName are required',
    });
    return;
  }

  const registration = await upsertDeviceRegistration({
    deviceId,
    teamName,
    memberName,
    platform,
  });

  response.status(201).json(deviceRegistrationResponse(registration));
});

app.delete('/api/device-registrations/:deviceId', async (request, response) => {
  const deviceId = parseRequiredText(request.params.deviceId);
  if (!deviceId) {
    response.status(400).json({ message: 'deviceId is required' });
    return;
  }

  await deleteDeviceRegistration(deviceId);
  response.status(204).send();
});

app.get('/admin', (_request, response) => {
  response.type('html').send(adminPageHtml());
});

// 관리자 페이지 로그인용 세션입니다.
// 브라우저가 앱 내부 deviceId를 알 수는 없으므로 최초 1회 입력받고,
// 이후에는 HttpOnly 쿠키로 90일 동안 유지합니다.
app.post('/api/admin/session', async (request, response) => {
  const deviceId = parseRequiredText(request.body?.deviceId);
  if (!deviceId) {
    response.status(400).json({ message: 'deviceId is required' });
    return;
  }

  if (!(await isAdminDevice(deviceId))) {
    response.status(403).json({ message: 'Admin access is not allowed' });
    return;
  }

  response.setHeader('Set-Cookie', createAdminCookie(deviceId));
  response.json({ ok: true });
});

app.delete('/api/admin/session', (_request, response) => {
  response.setHeader('Set-Cookie', clearAdminCookie());
  response.status(204).send();
});

app.get('/api/admin/snapshot', requireAdminDevice, async (_request, response) => {
  // 관리자 화면 첫 렌더링에 필요한 모든 테이블을 한 번에 내려줍니다.
  // 작은 내부 도구라 API 호출 수보다 구현 단순성을 우선했습니다.
  response.json({
    menus: (await listMenuRows()).map((row) => ({
      date: row.date,
      breakfast: splitMenu(row.breakfastMenu),
      dinner: splitMenu(row.dinnerMenu),
    })),
    messages: await listMessageRows(),
    operatingHours: await listOperatingHoursRows(),
    deviceRegistrations: (await listDeviceRegistrationRows()).map(
      deviceRegistrationResponse,
    ),
  });
});

app.post('/api/admin/menus', requireAdminDevice, async (request, response) => {
  const date = parseDateQuery(request.body?.date);
  if (!date.ok) {
    response.status(400).json({ message: 'date is required in YYYY-MM-DD format' });
    return;
  }

  const menu: MenuRow = {
    date: date.value,
    breakfastMenu: readAdminMenuText(request.body?.breakfast),
    dinnerMenu: readAdminMenuText(request.body?.dinner),
  };
  await upsertMenu(menu);

  response.status(201).json({
    date: menu.date,
    breakfast: splitMenu(menu.breakfastMenu),
    dinner: splitMenu(menu.dinnerMenu),
  });
});

app.delete('/api/admin/menus/:date', requireAdminDevice, async (request, response) => {
  const date = parseDateQuery(request.params.date);
  if (!date.ok) {
    response.status(400).json({ message: date.message });
    return;
  }

  await deleteMenu(date.value);
  response.status(204).send();
});

app.post('/api/admin/messages', requireAdminDevice, async (request, response) => {
  const text = parseRequiredText(request.body?.text);
  if (!text) {
    response.status(400).json({ message: 'text is required' });
    return;
  }

  response.status(201).json(await createMessage(text));
});

app.put('/api/admin/messages/:id', requireAdminDevice, async (request, response) => {
  const id = parseRequiredText(request.params.id);
  const text = parseRequiredText(request.body?.text);
  if (!id || !text) {
    response.status(400).json({ message: 'id and text are required' });
    return;
  }

  const message = await updateMessage(id, text);
  if (!message) {
    response.status(404).json({ message: 'Message not found' });
    return;
  }

  response.json(message);
});

app.delete('/api/admin/messages/:id', requireAdminDevice, async (request, response) => {
  const id = parseRequiredText(request.params.id);
  if (!id) {
    response.status(400).json({ message: 'id is required' });
    return;
  }

  await deleteMessage(id);
  response.status(204).send();
});

app.post(
  '/api/admin/operating-hours',
  requireAdminDevice,
  async (request, response) => {
    const row = readOperatingHoursInput(request.body);
    if (!row) {
      response.status(400).json({ message: 'valid weekday and HH:MM times are required' });
      return;
    }

    await saveOperatingHours(row);
    response.status(201).json(row);
  },
);

app.put(
  '/api/admin/operating-hours/:weekday',
  requireAdminDevice,
  async (request, response) => {
    const weekday = parseWeekday(request.params.weekday);
    const row = readOperatingHoursInput({ ...request.body, weekday });
    if (!row) {
      response.status(400).json({ message: 'valid weekday and HH:MM times are required' });
      return;
    }

    await saveOperatingHours(row);
    response.json(row);
  },
);

app.delete(
  '/api/admin/operating-hours/:weekday',
  requireAdminDevice,
  async (request, response) => {
    const weekday = parseWeekday(request.params.weekday);
    if (!weekday) {
      response.status(400).json({ message: 'weekday must be 1 through 7' });
      return;
    }

    await deleteOperatingHours(weekday);
    response.status(204).send();
  },
);

app.post(
  '/api/admin/device-registrations',
  requireAdminDevice,
  async (request, response) => {
    const row = readDeviceRegistrationInput(request.body);
    if (!row) {
      response.status(400).json({
        message: 'deviceId, teamName, memberName, and approved are required',
      });
      return;
    }

    response.status(201).json(deviceRegistrationResponse(await saveDeviceRegistration(row)));
  },
);

app.put(
  '/api/admin/device-registrations/:deviceId',
  requireAdminDevice,
  async (request, response) => {
    const row = readDeviceRegistrationInput({
      ...request.body,
      deviceId: request.params.deviceId,
    });
    if (!row) {
      response.status(400).json({
        message: 'deviceId, teamName, memberName, and approved are required',
      });
      return;
    }

    response.json(deviceRegistrationResponse(await saveDeviceRegistration(row)));
  },
);

app.delete(
  '/api/admin/device-registrations/:deviceId',
  requireAdminDevice,
  async (request, response) => {
    const deviceId = parseRequiredText(request.params.deviceId);
    if (!deviceId) {
      response.status(400).json({ message: 'deviceId is required' });
      return;
    }

    await deleteDeviceRegistration(deviceId);
    response.status(204).send();
  },
);

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
  // 서버리스 환경에서는 여러 요청이 동시에 들어올 수 있어 schema 생성 promise를
  // 공유합니다. 같은 인스턴스 안에서는 테이블 생성이 한 번만 실행됩니다.
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
  // 운영 DB가 비어 있어도 첫 요청 시 필요한 테이블과 기본 운영시간을 갖추게 합니다.
  // seed 메뉴/문구는 개발과 초기 확인용이며, 실제 데이터는 관리자 페이지에서 수정합니다.
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

  await client`
    create table if not exists device_registrations (
      device_id text primary key,
      team_name text not null,
      member_name text not null,
      approved char(1) not null default 'N',
      platform text not null default 'unknown',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      constraint device_registrations_approved_check
        check (approved in ('Y', 'N'))
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

async function listMenuRows(): Promise<MenuRow[]> {
  const client = await database();
  if (!client) {
    return [...memoryMenuRows].sort((a, b) => a.date.localeCompare(b.date));
  }

  const rows = (await client`
    select
      date::text as date,
      breakfast_menu as "breakfastMenu",
      dinner_menu as "dinnerMenu"
    from menus
    order by date
  `) as QueryRow[];

  return rows.map(menuRowFromQuery);
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

async function deleteMenu(date: string): Promise<void> {
  const client = await database();
  if (!client) {
    const index = memoryMenuRows.findIndex((row) => row.date === date);
    if (index >= 0) {
      memoryMenuRows.splice(index, 1);
    }
    return;
  }

  await client`
    delete from menus
    where date = ${date}
  `;
}

async function listMessageRows(): Promise<MessageRow[]> {
  const client = await database();
  if (!client) {
    return [...memoryMessageRows].sort((a, b) => Number(a.id) - Number(b.id));
  }

  const rows = (await client`
    select id::text, text
    from messages
    order by id
  `) as QueryRow[];

  return rows.map(messageRowFromQuery);
}

async function createMessage(text: string): Promise<MessageRow> {
  const client = await database();
  if (!client) {
    const nextId =
      Math.max(0, ...memoryMessageRows.map((row) => Number(row.id) || 0)) + 1;
    const row = { id: String(nextId), text };
    memoryMessageRows.push(row);
    return row;
  }

  const rows = (await client`
    insert into messages (text)
    values (${text})
    returning id::text, text
  `) as QueryRow[];

  return messageRowFromQuery(rows[0]);
}

async function updateMessage(
  id: string,
  text: string,
): Promise<MessageRow | undefined> {
  const client = await database();
  if (!client) {
    const row = memoryMessageRows.find((message) => message.id === id);
    if (!row) return undefined;
    row.text = text;
    return row;
  }

  const rows = (await client`
    update messages
    set text = ${text}
    where id = ${id}
    returning id::text, text
  `) as QueryRow[];

  return rows[0] ? messageRowFromQuery(rows[0]) : undefined;
}

async function deleteMessage(id: string): Promise<void> {
  const client = await database();
  if (!client) {
    const index = memoryMessageRows.findIndex((message) => message.id === id);
    if (index >= 0) {
      memoryMessageRows.splice(index, 1);
    }
    return;
  }

  await client`
    delete from messages
    where id = ${id}
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

async function listOperatingHoursRows(): Promise<OperatingHoursRow[]> {
  const client = await database();
  if (!client) {
    return [...memoryOperatingHoursRows].sort(
      (a, b) => a.weekday - b.weekday,
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
    order by weekday
  `) as QueryRow[];

  return rows.map(operatingHoursRowFromQuery);
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

async function saveOperatingHours(row: OperatingHoursRow): Promise<void> {
  const client = await database();
  if (!client) {
    const index = memoryOperatingHoursRows.findIndex(
      (hoursRow) => hoursRow.weekday === row.weekday,
    );
    if (index >= 0) {
      memoryOperatingHoursRows[index] = row;
    } else {
      memoryOperatingHoursRows.push(row);
    }
    return;
  }

  await upsertOperatingHours(client, row);
}

async function deleteOperatingHours(weekday: number): Promise<void> {
  const client = await database();
  if (!client) {
    const index = memoryOperatingHoursRows.findIndex(
      (hoursRow) => hoursRow.weekday === weekday,
    );
    if (index >= 0) {
      memoryOperatingHoursRows.splice(index, 1);
    }
    return;
  }

  await client`
    delete from operating_hours
    where weekday = ${weekday}
  `;
}

async function getDeviceRegistration(
  deviceId: string,
): Promise<DeviceRegistrationRow | undefined> {
  const client = await database();
  if (!client) {
    return memoryDeviceRegistrationRows.find((row) => row.deviceId === deviceId);
  }

  const rows = (await client`
    select
      device_id as "deviceId",
      team_name as "teamName",
      member_name as "memberName",
      approved,
      platform,
      created_at::text as "createdAt",
      updated_at::text as "updatedAt"
    from device_registrations
    where device_id = ${deviceId}
    limit 1
  `) as QueryRow[];

  return rows[0] ? deviceRegistrationRowFromQuery(rows[0]) : undefined;
}

async function listDeviceRegistrationRows(): Promise<DeviceRegistrationRow[]> {
  const client = await database();
  if (!client) {
    return [...memoryDeviceRegistrationRows].sort((a, b) =>
      a.createdAt.localeCompare(b.createdAt),
    );
  }

  const rows = (await client`
    select
      device_id as "deviceId",
      team_name as "teamName",
      member_name as "memberName",
      approved,
      platform,
      created_at::text as "createdAt",
      updated_at::text as "updatedAt"
    from device_registrations
    order by created_at
  `) as QueryRow[];

  return rows.map(deviceRegistrationRowFromQuery);
}

async function listApprovedDeviceRegistrationRows(): Promise<
  DeviceRegistrationRow[]
> {
  return (await listDeviceRegistrationRows()).filter(
    (row) => row.approved === 'Y',
  );
}

async function upsertDeviceRegistration(input: {
  deviceId: string;
  teamName: string;
  memberName: string;
  platform: string;
}): Promise<DeviceRegistrationRow> {
  const now = new Date().toISOString();
  const client = await database();

  if (!client) {
    const existingIndex = memoryDeviceRegistrationRows.findIndex(
      (row) => row.deviceId === input.deviceId,
    );
    const existing = memoryDeviceRegistrationRows[existingIndex];
    const row: DeviceRegistrationRow = {
      deviceId: input.deviceId,
      teamName: input.teamName,
      memberName: input.memberName,
      approved: existing?.approved ?? 'N',
      platform: input.platform,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };

    if (existingIndex >= 0) {
      memoryDeviceRegistrationRows[existingIndex] = row;
    } else {
      memoryDeviceRegistrationRows.push(row);
    }

    return row;
  }

  const rows = (await client`
    insert into device_registrations (
      device_id,
      team_name,
      member_name,
      approved,
      platform
    )
    values (
      ${input.deviceId},
      ${input.teamName},
      ${input.memberName},
      'N',
      ${input.platform}
    )
    on conflict (device_id) do update set
      team_name = excluded.team_name,
      member_name = excluded.member_name,
      platform = excluded.platform,
      updated_at = now()
    returning
      device_id as "deviceId",
      team_name as "teamName",
      member_name as "memberName",
      approved,
      platform,
      created_at::text as "createdAt",
      updated_at::text as "updatedAt"
  `) as QueryRow[];

  return deviceRegistrationRowFromQuery(rows[0]);
}

async function saveDeviceRegistration(input: {
  deviceId: string;
  teamName: string;
  memberName: string;
  approved: 'Y' | 'N';
  platform: string;
}): Promise<DeviceRegistrationRow> {
  const now = new Date().toISOString();
  const client = await database();

  if (!client) {
    const existingIndex = memoryDeviceRegistrationRows.findIndex(
      (row) => row.deviceId === input.deviceId,
    );
    const existing = memoryDeviceRegistrationRows[existingIndex];
    const row: DeviceRegistrationRow = {
      deviceId: input.deviceId,
      teamName: input.teamName,
      memberName: input.memberName,
      approved: input.approved,
      platform: input.platform,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };

    if (existingIndex >= 0) {
      memoryDeviceRegistrationRows[existingIndex] = row;
    } else {
      memoryDeviceRegistrationRows.push(row);
    }

    return row;
  }

  const rows = (await client`
    insert into device_registrations (
      device_id,
      team_name,
      member_name,
      approved,
      platform
    )
    values (
      ${input.deviceId},
      ${input.teamName},
      ${input.memberName},
      ${input.approved},
      ${input.platform}
    )
    on conflict (device_id) do update set
      team_name = excluded.team_name,
      member_name = excluded.member_name,
      approved = excluded.approved,
      platform = excluded.platform,
      updated_at = now()
    returning
      device_id as "deviceId",
      team_name as "teamName",
      member_name as "memberName",
      approved,
      platform,
      created_at::text as "createdAt",
      updated_at::text as "updatedAt"
  `) as QueryRow[];

  return deviceRegistrationRowFromQuery(rows[0]);
}

async function deleteDeviceRegistration(deviceId: string): Promise<void> {
  const client = await database();
  if (!client) {
    const index = memoryDeviceRegistrationRows.findIndex(
      (row) => row.deviceId === deviceId,
    );
    if (index >= 0) {
      memoryDeviceRegistrationRows.splice(index, 1);
    }
    return;
  }

  await client`
    delete from device_registrations
    where device_id = ${deviceId}
  `;
}

async function isApprovedDevice(deviceId: string | undefined): Promise<boolean> {
  if (!deviceId) return false;
  const registration = await getDeviceRegistration(deviceId);
  return registration?.approved === 'Y';
}

async function requireAdminDevice(
  request: express.Request,
  response: express.Response,
  next: express.NextFunction,
): Promise<void> {
  // 관리자 API는 두 경로를 허용합니다.
  // 1. 테스트/스크립트용 x-admin-device-id 헤더
  // 2. 관리자 페이지에서 발급한 HttpOnly 쿠키
  const deviceId = parseRequiredText(request.header('x-admin-device-id')) ?? getAdminCookieDeviceId(request);
  if (!deviceId) {
    response.status(401).json({ message: 'Admin device id is required' });
    return;
  }

  if (!(await isAdminDevice(deviceId))) {
    response.status(403).json({ message: 'Admin access is not allowed' });
    return;
  }

  next();
}

function getAdminCookieDeviceId(request: express.Request): string | undefined {
  const cookieHeader = request.header('cookie');
  if (!cookieHeader) return undefined;

  const cookies = cookieHeader.split(';').map((cookie) => cookie.trim());
  const prefix = `${adminCookieName}=`;
  const cookie = cookies.find((value) => value.startsWith(prefix));
  if (!cookie) return undefined;

  return parseRequiredText(decodeURIComponent(cookie.slice(prefix.length)));
}

function createAdminCookie(deviceId: string): string {
  return [
    `${adminCookieName}=${encodeURIComponent(deviceId)}`,
    'Path=/',
    'HttpOnly',
    'Secure',
    'SameSite=Lax',
    `Max-Age=${adminCookieMaxAgeSeconds}`,
  ].join('; ');
}

function clearAdminCookie(): string {
  return [
    `${adminCookieName}=`,
    'Path=/',
    'HttpOnly',
    'Secure',
    'SameSite=Lax',
    'Max-Age=0',
  ].join('; ');
}

async function isAdminDevice(deviceId: string): Promise<boolean> {
  const configuredAdminDeviceId = parseRequiredText(process.env.ADMIN_DEVICE_ID);
  const registration = await getDeviceRegistration(deviceId);
  if (configuredAdminDeviceId) {
    // 직원 기기가 여러 개 승인되어도 관리자 권한은 환경변수의 한 기기에 고정합니다.
    return deviceId === configuredAdminDeviceId && registration?.approved === 'Y';
  }

  // 개발/초기 운영 편의용 fallback입니다. 승인된 기기가 하나뿐이면 그 기기를
  // 관리자로 간주하지만, 실제 운영에서는 ADMIN_DEVICE_ID 설정을 권장합니다.
  const approvedDevices = await listApprovedDeviceRegistrationRows();
  return approvedDevices.length === 1 && approvedDevices[0].deviceId === deviceId;
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

function readAdminMenuText(value: unknown): string {
  const items = Array.isArray(value)
    ? value
    : String(value ?? '')
        .split(/\r?\n|,/)
        .map((item) => item.trim());

  return joinMenu(items.map((item) => String(item).trim()).filter(Boolean));
}

function parseRequiredText(value: unknown): string | undefined {
  const text = String(value ?? '').trim();
  return text || undefined;
}

function parseWeekday(value: unknown): number | undefined {
  const weekday = Number(value);
  if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) {
    return undefined;
  }

  return weekday;
}

function parseApprovalStatus(value: unknown): 'Y' | 'N' | undefined {
  const status = String(value ?? '').trim().toUpperCase();
  return status === 'Y' || status === 'N' ? status : undefined;
}

function isTimeText(value: string | undefined): value is string {
  return /^\d{2}:\d{2}$/.test(value ?? '');
}

function readOperatingHoursInput(value: unknown): OperatingHoursRow | undefined {
  const input = (value ?? {}) as Record<string, unknown>;
  const weekday = parseWeekday(input.weekday);
  const breakfastStart = parseRequiredText(input.breakfastStart);
  const breakfastEnd = parseRequiredText(input.breakfastEnd);
  const dinnerStart = parseRequiredText(input.dinnerStart);
  const dinnerEnd = parseRequiredText(input.dinnerEnd);

  if (
    !weekday ||
    !isTimeText(breakfastStart) ||
    !isTimeText(breakfastEnd) ||
    !isTimeText(dinnerStart) ||
    !isTimeText(dinnerEnd)
  ) {
    return undefined;
  }

  return {
    weekday,
    breakfastStart,
    breakfastEnd,
    dinnerStart,
    dinnerEnd,
  };
}

function readDeviceRegistrationInput(
  value: unknown,
):
  | {
      deviceId: string;
      teamName: string;
      memberName: string;
      approved: 'Y' | 'N';
      platform: string;
    }
  | undefined {
  const input = (value ?? {}) as Record<string, unknown>;
  const deviceId = parseRequiredText(input.deviceId);
  const teamName = parseRequiredText(input.teamName);
  const memberName = parseRequiredText(input.memberName);
  const approved = parseApprovalStatus(input.approved);
  const platform = parseRequiredText(input.platform) ?? 'unknown';

  if (!deviceId || !teamName || !memberName || !approved) {
    return undefined;
  }

  return {
    deviceId,
    teamName,
    memberName,
    approved,
    platform,
  };
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
  // 아침 종료 시각까지는 아침 식단을 보여주고, 이후에는 저녁 식단을 보여줍니다.
  // 기준 시각은 클라이언트가 넘긴 at을 한국 시간으로 해석합니다.
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

function deviceRegistrationRowFromQuery(row: QueryRow): DeviceRegistrationRow {
  return {
    deviceId: String(row.deviceId),
    teamName: String(row.teamName ?? ''),
    memberName: String(row.memberName ?? ''),
    approved: row.approved === 'Y' ? 'Y' : 'N',
    platform: String(row.platform ?? 'unknown'),
    createdAt: String(row.createdAt ?? ''),
    updatedAt: String(row.updatedAt ?? ''),
  };
}

function deviceRegistrationResponse(row: DeviceRegistrationRow) {
  return {
    deviceId: row.deviceId,
    teamName: row.teamName,
    memberName: row.memberName,
    approved: row.approved === 'Y',
    approvalStatus: row.approved,
    platform: row.platform,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

function adminPageHtml(): string {
  // 별도 프론트엔드 빌드 없이 서버 한 파일로 관리 페이지를 배포하기 위해
  // HTML/CSS/JS를 문자열로 제공합니다. 규모가 커지면 server/admin 같은 정적 파일로
  // 분리하는 것이 다음 단계입니다.
  return `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>오늘 밥 뭐야 관리자</title>
  <style>
    :root {
      color: #191919;
      background: #fafafa;
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo",
        "Noto Sans KR", sans-serif;
    }
    * { box-sizing: border-box; }
    body { margin: 0; padding: 28px; }
    main { max-width: 1180px; margin: 0 auto; }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 18px;
    }
    h1 { margin: 0; font-size: 26px; }
    h2 { margin: 0 0 14px; font-size: 18px; }
    section, .login {
      background: #fff;
      border: 1px solid #e7e7e7;
      border-radius: 8px;
      padding: 18px;
      margin-bottom: 16px;
      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 10px;
      margin-bottom: 12px;
    }
    label {
      display: grid;
      gap: 6px;
      color: #606060;
      font-size: 12px;
      font-weight: 700;
    }
    input, textarea, select {
      width: 100%;
      border: 1px solid #d8d8d8;
      border-radius: 8px;
      padding: 10px 12px;
      color: #191919;
      background: #fff;
      font: inherit;
      font-size: 14px;
    }
    textarea { min-height: 112px; resize: vertical; line-height: 1.5; }
    button {
      border: 0;
      border-radius: 8px;
      padding: 10px 14px;
      color: #fff;
      background: #ff5a52;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
    }
    button.secondary { background: #555; }
    button.ghost {
      color: #333;
      background: #f1f1f1;
    }
    button.danger { background: #2e2e2e; }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      table-layout: fixed;
    }
    th, td {
      border-top: 1px solid #ededed;
      padding: 10px 8px;
      text-align: left;
      vertical-align: top;
      word-break: break-word;
    }
    th { color: #666; font-size: 12px; }
    .actions { display: flex; gap: 6px; flex-wrap: wrap; }
    .status { min-height: 22px; margin: 0 0 12px; color: #ff5a52; }
    .muted { color: #777; font-size: 13px; }
    .hidden { display: none; }
    @media (max-width: 720px) {
      body { padding: 16px; }
      header { align-items: flex-start; flex-direction: column; }
      table { display: block; overflow-x: auto; white-space: nowrap; }
      th, td { min-width: 120px; white-space: normal; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>오늘 밥 뭐야 관리자</h1>
        <p class="muted">처음 한 번 인증하면 이 브라우저에서 90일 동안 유지됩니다.</p>
      </div>
      <div class="actions">
        <button class="ghost" id="reloadButton">새로고침</button>
        <button class="secondary" id="logoutButton">기기 ID 변경</button>
      </div>
    </header>

    <div class="login" id="loginPanel">
      <h2>관리자 기기 인증</h2>
      <p class="muted">가입 승인된 내 기기 ID를 한 번만 입력하세요. 이후에는 서버 세션으로 유지됩니다.</p>
      <div class="grid">
        <label>기기 ID
          <input id="adminDeviceIdInput" autocomplete="off" />
        </label>
      </div>
      <button id="saveDeviceIdButton">인증하고 열기</button>
    </div>

    <p class="status" id="status"></p>

    <div id="adminPanel" class="hidden">
      <section>
        <h2>식단</h2>
        <div class="grid">
          <label>날짜
            <input id="menuDate" type="date" />
          </label>
          <label>아침 메뉴
            <textarea id="menuBreakfast" placeholder="한 줄에 하나씩 입력"></textarea>
          </label>
          <label>저녁 메뉴
            <textarea id="menuDinner" placeholder="한 줄에 하나씩 입력"></textarea>
          </label>
        </div>
        <div class="actions">
          <button id="saveMenuButton">식단 저장</button>
          <button class="ghost" id="clearMenuButton">입력 초기화</button>
        </div>
        <table>
          <thead><tr><th>날짜</th><th>아침</th><th>저녁</th><th>작업</th></tr></thead>
          <tbody id="menusBody"></tbody>
        </table>
      </section>

      <section>
        <h2>흐르는 문구</h2>
        <div class="grid">
          <label>문구
            <input id="messageText" />
          </label>
        </div>
        <button id="addMessageButton">문구 추가</button>
        <table>
          <thead><tr><th style="width:80px">ID</th><th>문구</th><th style="width:180px">작업</th></tr></thead>
          <tbody id="messagesBody"></tbody>
        </table>
      </section>

      <section>
        <h2>운영 시간</h2>
        <table>
          <thead>
            <tr>
              <th>요일</th><th>아침 시작</th><th>아침 종료</th>
              <th>저녁 시작</th><th>저녁 종료</th><th>작업</th>
            </tr>
          </thead>
          <tbody id="hoursBody"></tbody>
        </table>
      </section>

      <section>
        <h2>가입 기기</h2>
        <div class="grid">
          <label>기기 ID
            <input id="deviceId" />
          </label>
          <label>팀명
            <input id="deviceTeamName" />
          </label>
          <label>이름
            <input id="deviceMemberName" />
          </label>
          <label>승인
            <select id="deviceApproved"><option value="N">N</option><option value="Y">Y</option></select>
          </label>
          <label>플랫폼
            <input id="devicePlatform" value="admin" />
          </label>
        </div>
        <div class="actions">
          <button id="saveDeviceButton">기기 저장</button>
          <button class="ghost" id="clearDeviceButton">입력 초기화</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>기기 ID</th><th>팀명</th><th>이름</th><th>승인</th>
              <th>플랫폼</th><th>생성</th><th>수정</th><th>작업</th>
            </tr>
          </thead>
          <tbody id="devicesBody"></tbody>
        </table>
      </section>
    </div>
  </main>

  <script>
    var state = { menus: [], messages: [], operatingHours: [], deviceRegistrations: [] };
    var deviceIdKey = "todayBobAdminDeviceId";
    var weekdayNames = ["", "월", "화", "수", "목", "금", "토", "일"];
    var adminDeviceIdInput = document.getElementById("adminDeviceIdInput");
    var loginPanel = document.getElementById("loginPanel");
    var adminPanel = document.getElementById("adminPanel");
    var statusEl = document.getElementById("status");

    function adminDeviceId() {
      return window.localStorage.getItem(deviceIdKey) || "";
    }

    function setStatus(message, isError) {
      statusEl.textContent = message || "";
      statusEl.style.color = isError ? "#ff5a52" : "#2f7d32";
    }

    function escapeHtml(value) {
      return String(value || "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
    }

    async function requestJson(path, options) {
      var nextOptions = options || {};
      var headers = Object.assign({ "Content-Type": "application/json" }, nextOptions.headers || {});
      if (adminDeviceId()) {
        headers["x-admin-device-id"] = adminDeviceId();
      }
      var response = await fetch(path, Object.assign({}, nextOptions, {
        headers: headers,
        credentials: "same-origin"
      }));
      if (response.status === 204) return null;
      var text = await response.text();
      var data = text ? JSON.parse(text) : null;
      if (!response.ok) {
        throw new Error((data && data.message) || "요청에 실패했어요");
      }
      return data;
    }

    async function loadSnapshot() {
      try {
        setStatus("불러오는 중...", false);
        state = await requestJson("/api/admin/snapshot");
        loginPanel.classList.add("hidden");
        adminPanel.classList.remove("hidden");
        renderAll();
        setStatus("불러왔어요.", false);
      } catch (error) {
        loginPanel.classList.remove("hidden");
        adminPanel.classList.add("hidden");
        setStatus(error.message, true);
      }
    }

    function renderAll() {
      renderMenus();
      renderMessages();
      renderHours();
      renderDevices();
    }

    function renderMenus() {
      document.getElementById("menusBody").innerHTML = state.menus.map(function(row) {
        return "<tr><td>" + escapeHtml(row.date) + "</td><td>" +
          escapeHtml((row.breakfast || []).join("\\n")).replaceAll("\\n", "<br>") +
          "</td><td>" +
          escapeHtml((row.dinner || []).join("\\n")).replaceAll("\\n", "<br>") +
          "</td><td><div class='actions'>" +
          "<button class='ghost' onclick='editMenu(" + JSON.stringify(row.date) + ")'>수정</button>" +
          "<button class='danger' onclick='deleteMenu(" + JSON.stringify(row.date) + ")'>삭제</button>" +
          "</div></td></tr>";
      }).join("");
    }

    function renderMessages() {
      document.getElementById("messagesBody").innerHTML = state.messages.map(function(row) {
        return "<tr><td>" + escapeHtml(row.id) + "</td><td>" +
          "<input id='message-" + escapeHtml(row.id) + "' value='" + escapeHtml(row.text) + "' />" +
          "</td><td><div class='actions'>" +
          "<button class='ghost' onclick='updateMessage(" + JSON.stringify(row.id) + ")'>저장</button>" +
          "<button class='danger' onclick='deleteMessage(" + JSON.stringify(row.id) + ")'>삭제</button>" +
          "</div></td></tr>";
      }).join("");
    }

    function renderHours() {
      var rows = [];
      for (var weekday = 1; weekday <= 7; weekday += 1) {
        var row = state.operatingHours.find(function(item) { return item.weekday === weekday; }) || {
          weekday: weekday,
          breakfastStart: "",
          breakfastEnd: "",
          dinnerStart: "",
          dinnerEnd: ""
        };
        rows.push("<tr><td>" + weekdayNames[weekday] + "</td>" +
          hourInput(weekday, "breakfastStart", row.breakfastStart) +
          hourInput(weekday, "breakfastEnd", row.breakfastEnd) +
          hourInput(weekday, "dinnerStart", row.dinnerStart) +
          hourInput(weekday, "dinnerEnd", row.dinnerEnd) +
          "<td><div class='actions'>" +
          "<button class='ghost' onclick='saveHours(" + weekday + ")'>저장</button>" +
          "<button class='danger' onclick='deleteHours(" + weekday + ")'>삭제</button>" +
          "</div></td></tr>");
      }
      document.getElementById("hoursBody").innerHTML = rows.join("");
    }

    function hourInput(weekday, key, value) {
      return "<td><input type='time' id='hours-" + weekday + "-" + key +
        "' value='" + escapeHtml(value) + "' /></td>";
    }

    function renderDevices() {
      document.getElementById("devicesBody").innerHTML = state.deviceRegistrations.map(function(row) {
        return "<tr><td>" + escapeHtml(row.deviceId) + "</td><td>" +
          escapeHtml(row.teamName) + "</td><td>" + escapeHtml(row.memberName) +
          "</td><td>" + escapeHtml(row.approvalStatus) + "</td><td>" +
          escapeHtml(row.platform) + "</td><td>" + escapeHtml(row.createdAt) +
          "</td><td>" + escapeHtml(row.updatedAt) + "</td><td><div class='actions'>" +
          "<button class='ghost' onclick='editDevice(" + JSON.stringify(row.deviceId) + ")'>수정</button>" +
          "<button class='danger' onclick='deleteDevice(" + JSON.stringify(row.deviceId) + ")'>삭제</button>" +
          "</div></td></tr>";
      }).join("");
    }

    window.editMenu = function(date) {
      var row = state.menus.find(function(item) { return item.date === date; });
      if (!row) return;
      document.getElementById("menuDate").value = row.date;
      document.getElementById("menuBreakfast").value = (row.breakfast || []).join("\\n");
      document.getElementById("menuDinner").value = (row.dinner || []).join("\\n");
      window.scrollTo({ top: 0, behavior: "smooth" });
    };

    window.deleteMenu = async function(date) {
      if (!confirm(date + " 식단을 삭제할까요?")) return;
      await requestJson("/api/admin/menus/" + encodeURIComponent(date), { method: "DELETE" });
      await loadSnapshot();
    };

    window.updateMessage = async function(id) {
      var text = document.getElementById("message-" + id).value;
      await requestJson("/api/admin/messages/" + encodeURIComponent(id), {
        method: "PUT",
        body: JSON.stringify({ text: text })
      });
      await loadSnapshot();
    };

    window.deleteMessage = async function(id) {
      if (!confirm("문구를 삭제할까요?")) return;
      await requestJson("/api/admin/messages/" + encodeURIComponent(id), { method: "DELETE" });
      await loadSnapshot();
    };

    window.saveHours = async function(weekday) {
      var payload = {
        weekday: weekday,
        breakfastStart: document.getElementById("hours-" + weekday + "-breakfastStart").value,
        breakfastEnd: document.getElementById("hours-" + weekday + "-breakfastEnd").value,
        dinnerStart: document.getElementById("hours-" + weekday + "-dinnerStart").value,
        dinnerEnd: document.getElementById("hours-" + weekday + "-dinnerEnd").value
      };
      await requestJson("/api/admin/operating-hours/" + weekday, {
        method: "PUT",
        body: JSON.stringify(payload)
      });
      await loadSnapshot();
    };

    window.deleteHours = async function(weekday) {
      if (!confirm(weekdayNames[weekday] + "요일 운영 시간을 삭제할까요?")) return;
      await requestJson("/api/admin/operating-hours/" + weekday, { method: "DELETE" });
      await loadSnapshot();
    };

    window.editDevice = function(deviceId) {
      var row = state.deviceRegistrations.find(function(item) { return item.deviceId === deviceId; });
      if (!row) return;
      document.getElementById("deviceId").value = row.deviceId;
      document.getElementById("deviceTeamName").value = row.teamName;
      document.getElementById("deviceMemberName").value = row.memberName;
      document.getElementById("deviceApproved").value = row.approvalStatus;
      document.getElementById("devicePlatform").value = row.platform;
    };

    window.deleteDevice = async function(deviceId) {
      if (!confirm("기기를 삭제할까요? 관리자 본인 기기를 삭제하면 다시 접근할 수 없어요.")) return;
      await requestJson("/api/admin/device-registrations/" + encodeURIComponent(deviceId), {
        method: "DELETE"
      });
      await loadSnapshot();
    };

    document.getElementById("saveDeviceIdButton").addEventListener("click", async function() {
      var nextDeviceId = adminDeviceIdInput.value.trim();
      if (!nextDeviceId) {
        setStatus("기기 ID를 입력해 주세요.", true);
        return;
      }

      try {
        setStatus("인증하는 중...", false);
        await requestJson("/api/admin/session", {
          method: "POST",
          body: JSON.stringify({ deviceId: nextDeviceId })
        });
        window.localStorage.setItem(deviceIdKey, nextDeviceId);
        await loadSnapshot();
      } catch (error) {
        setStatus(error.message, true);
      }
    });

    document.getElementById("logoutButton").addEventListener("click", async function() {
      try {
        await requestJson("/api/admin/session", { method: "DELETE" });
      } catch (error) {
      }
      window.localStorage.removeItem(deviceIdKey);
      adminDeviceIdInput.value = "";
      loginPanel.classList.remove("hidden");
      adminPanel.classList.add("hidden");
      setStatus("", false);
    });

    document.getElementById("reloadButton").addEventListener("click", loadSnapshot);

    document.getElementById("saveMenuButton").addEventListener("click", async function() {
      await requestJson("/api/admin/menus", {
        method: "POST",
        body: JSON.stringify({
          date: document.getElementById("menuDate").value,
          breakfast: document.getElementById("menuBreakfast").value,
          dinner: document.getElementById("menuDinner").value
        })
      });
      await loadSnapshot();
    });

    document.getElementById("clearMenuButton").addEventListener("click", function() {
      document.getElementById("menuDate").value = "";
      document.getElementById("menuBreakfast").value = "";
      document.getElementById("menuDinner").value = "";
    });

    document.getElementById("addMessageButton").addEventListener("click", async function() {
      await requestJson("/api/admin/messages", {
        method: "POST",
        body: JSON.stringify({ text: document.getElementById("messageText").value })
      });
      document.getElementById("messageText").value = "";
      await loadSnapshot();
    });

    document.getElementById("saveDeviceButton").addEventListener("click", async function() {
      await requestJson("/api/admin/device-registrations", {
        method: "POST",
        body: JSON.stringify({
          deviceId: document.getElementById("deviceId").value,
          teamName: document.getElementById("deviceTeamName").value,
          memberName: document.getElementById("deviceMemberName").value,
          approved: document.getElementById("deviceApproved").value,
          platform: document.getElementById("devicePlatform").value
        })
      });
      await loadSnapshot();
    });

    document.getElementById("clearDeviceButton").addEventListener("click", function() {
      document.getElementById("deviceId").value = "";
      document.getElementById("deviceTeamName").value = "";
      document.getElementById("deviceMemberName").value = "";
      document.getElementById("deviceApproved").value = "N";
      document.getElementById("devicePlatform").value = "admin";
    });

    adminDeviceIdInput.value = adminDeviceId();
    loadSnapshot();
  </script>
</body>
</html>`;
}
