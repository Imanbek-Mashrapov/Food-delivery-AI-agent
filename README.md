# Food Delivery — AI Agent for Relational Database

**Databases Course — Final Project**

A normalized 9-table MySQL database loaded with 20,000 real food-delivery orders, plus a natural-language AI agent (LangChain + Gemini) that lets anyone ask the data questions in plain English.

---

## What's in this repo

| File | What it does |
|------|--------------|
| `01_schema.sql`            | Creates the database, 9 tables, FKs, and 8 indexes |
| `02_views_procedures.sql`  | 5 analytical views + 5 stored procedures |
| `etl_load.py`              | Cleans the CSV and populates all 9 tables |
| `food_delivery_dataset.csv`| Raw dataset (20,000 orders) |
| `main.ipynb`               | Demo notebook — DB queries, charts, AI agent |
| `requirements.txt`         | Python dependencies |
| `.env.example`             | Template for credentials (copy to `.env`) |

---

## Setup — step by step

### Step 1. Install MySQL

If you don't already have it:

- **Windows / Mac:** download MySQL Community Server + MySQL Workbench from https://dev.mysql.com/downloads/
- **Linux:** `sudo apt install mysql-server` (or your distro's equivalent)

Test it works:

```bash
mysql -u root -p
```

You should get a `mysql>` prompt. Type `exit;` to leave.

### Step 2. Install Python 3.10+ and the dependencies

```bash
python --version           # should be 3.10 or newer
pip install -r requirements.txt
```

> If you hit permission errors on Linux/Mac, use `pip install --user -r requirements.txt`.

### Step 3. Get a Google Gemini API key

It's **free** for the Flash model.

1. Go to https://aistudio.google.com/app/apikey
2. Sign in with a Google account
3. Click "Create API key" → copy the key

### Step 4. Configure credentials

```bash
cp .env.example .env
```

Open `.env` in a text editor and fill in:

```
DB_PASSWORD=<your MySQL root password>
GOOGLE_API_KEY=<the key from step 3>
```

### Step 5. Build the database

Open **MySQL Workbench**, connect to your local server, and run:

1. **`01_schema.sql`** — creates the database, tables, FKs, indexes
2. **(skip for now)** — we'll come back to `02_views_procedures.sql` after data is loaded

Or from the command line:

```bash
mysql -u root -p < 01_schema.sql
```

### Step 6. Load the data

```bash
python etl_load.py
```

Expected output ends with:

```
✅ all data committed

[verify] final row counts
  locations           10
  cuisines             5
  routes               5
  restaurants        100
  customers       20,000
  orders          20,000
  order_items     20,000
  deliveries      20,000
  feedback        20,000
```

### Step 7. Build the analytical layer

Now that data is loaded, run:

```bash
mysql -u root -p < 02_views_procedures.sql
```

(Or paste the file into MySQL Workbench and run it.)

This creates 5 views and 5 stored procedures.

### Step 8. Run the notebook

```bash
jupyter notebook main.ipynb
```

Run the cells top-to-bottom. The **last few cells** are the AI agent demo — that's the showpiece.

---

## Architecture in one diagram

```
                           ┌───────────────────────┐
   "Which city has the     │   LangChain SQL Agent │
    most revenue?"   ───►  │   + Gemini (Flash)    │  ──┐
                           └───────────────────────┘    │
                                                        ▼
                               ┌────────────────────────────┐
                               │   MySQL: food_delivery     │
                               │   9 tables · 5 views · 5   │
                               │   stored procedures        │
                               └────────────────────────────┘
                                            │
                                            ▼
                       Natural-language answer + the SQL it ran
```

---

## The 4 problems we solve

1. **Delivery delay drivers** — which factors (traffic, weather, method, route) cause the most delay?
2. **Route efficiency validity** — does the recorded `route_efficiency` score actually predict shorter delays?
3. **Satisfaction drivers** — what combination of food temperature, freshness, packaging maximizes satisfaction?
4. **Loyalty programme ROI** — do members spend more per order? Is the programme paying for itself?

Each problem is encapsulated in its own SQL view (`vw_delay_drivers`, `vw_route_performance`, `vw_satisfaction_drivers`, `vw_loyalty_analysis`) so the AI agent has well-named, single-purpose targets to query.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Access denied for user`           | Check `DB_USER` / `DB_PASSWORD` in `.env` |
| `Unknown database 'food_delivery'` | Run `01_schema.sql` first |
| `MySQL 8 authentication error`     | `ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'your_password';` |
| `google.api_core.exceptions.ResourceExhausted` | Free Gemini tier rate limit — wait 60 seconds and retry |
| Notebook can't import `langchain_google_genai` | `pip install -U langchain-google-genai` |
| Pandas `read_sql` warning about engine | Safe to ignore — passing the SQLAlchemy engine is the modern way |
| AI agent returns wrong SQL | Try rephrasing — be specific about the metric (e.g. "average" vs "total") |
