import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';

dotenv.config();

type MealType = 'breakfast' | 'lunch' | 'dinner';

type Meal = {
  id: string;
  date: string;
  type: MealType;
  title: string;
  items: string[];
};

const app = express();
const port = Number(process.env.PORT ?? 3000);

app.use(cors());
app.use(express.json());

app.get('/health', (_request, response) => {
  response.json({ status: 'ok' });
});

app.get('/api/menus', (request, response) => {
  const date = String(request.query.date ?? '');

  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    response.status(400).json({
      message: 'date query is required in YYYY-MM-DD format',
    });
    return;
  }

  const meals: Meal[] = [];

  response.json({
    date,
    meals,
  });
});

app.listen(port, () => {
  console.log(`today-bob server listening on http://localhost:${port}`);
});
