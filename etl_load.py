"""
ETL  –  food_delivery_dataset.csv  →  MySQL (food_delivery)
============================================================
Run:
    python etl_load.py                           # uses defaults below
    python etl_load.py --csv path/to/file.csv    # custom path

Requirements:
    pip install pandas mysql-connector-python python-dotenv
"""

import argparse
import os
import sys
import pandas as pd
import mysql.connector
from mysql.connector import Error
from dotenv import load_dotenv

# ── Config ────────────────────────────────────────────────────────────────────
load_dotenv()                          # optional: store creds in .env

DB_CONFIG = {
    "host":     os.getenv("DB_HOST",     "localhost"),
    "port":     int(os.getenv("DB_PORT", 3306)),
    "user":     os.getenv("DB_USER",     "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME",     "food_delivery"),
    "autocommit": False,
}

DEFAULT_CSV = os.path.join(os.path.dirname(__file__), "..", "data", "food_delivery_dataset.csv")
BATCH_SIZE  = 500   # rows per INSERT batch

# ── Helpers ───────────────────────────────────────────────────────────────────

def get_connection():
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        print(f"[DB] Connected to {DB_CONFIG['database']} on {DB_CONFIG['host']}")
        return conn
    except Error as e:
        sys.exit(f"[DB] Connection failed: {e}")


def executemany_batch(cursor, sql: str, rows: list, batch_size: int = BATCH_SIZE):
    """Insert rows in batches and return total inserted."""
    total = 0
    for i in range(0, len(rows), batch_size):
        cursor.executemany(sql, rows[i : i + batch_size])
        total += cursor.rowcount
    return total


# ── Cleaning ──────────────────────────────────────────────────────────────────

def clean(df: pd.DataFrame) -> pd.DataFrame:
    print(f"[ETL] Raw rows: {len(df)}")

    # ── Booleans ──────────────────────────────────────────────────────────────
    for col in ("loyalty_program", "small_route", "bike_friendly_route", "traffic_avoidance"):
        if col in df.columns:
            df[col] = df[col].map(
                lambda v: True if str(v).strip().lower() in ("yes", "true", "1") else False
            )

    # ── Datetimes ─────────────────────────────────────────────────────────────
    for col in ("order_time", "delivery_time"):
        df[col] = pd.to_datetime(df[col], errors="coerce")

    # ── Numeric clamp / coerce ────────────────────────────────────────────────
    df["age"]               = pd.to_numeric(df["age"],               errors="coerce").clip(0, 120)
    df["order_history"]     = pd.to_numeric(df["order_history"],     errors="coerce").clip(0)
    df["delivery_distance"] = pd.to_numeric(df["delivery_distance"], errors="coerce").clip(0)
    df["delivery_delay"]    = pd.to_numeric(df["delivery_delay"],    errors="coerce")
    df["order_value"]       = pd.to_numeric(df["order_value"],       errors="coerce").clip(0)
    df["route_efficiency"]  = pd.to_numeric(df["route_efficiency"],  errors="coerce").clip(0, 1)

    for col in ("customer_rating", "customer_satisfaction", "food_freshness", "packaging_quality"):
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # ── Strings: strip whitespace ─────────────────────────────────────────────
    str_cols = df.select_dtypes("object").columns
    df[str_cols] = df[str_cols].apply(lambda s: s.str.strip())

    # ── Drop duplicates ───────────────────────────────────────────────────────
    before = len(df)
    df.drop_duplicates(subset=["order_id"], inplace=True)
    print(f"[ETL] Dropped {before - len(df)} duplicate order_ids")

    # ── Drop rows missing critical keys ───────────────────────────────────────
    before = len(df)
    df.dropna(subset=["order_id", "customer_id", "restaurant_id"], inplace=True)
    print(f"[ETL] Dropped {before - len(df)} rows with null PKs/FKs")

    print(f"[ETL] Clean rows: {len(df)}")
    return df.reset_index(drop=True)


# ── Loaders ───────────────────────────────────────────────────────────────────

def load_locations(cursor, df) -> dict:
    cities = df["location"].dropna().unique().tolist()
    cursor.executemany(
        "INSERT IGNORE INTO locations (city) VALUES (%s)",
        [(c,) for c in cities],
    )
    cursor.execute("SELECT location_id, city FROM locations")
    return {row[1]: row[0] for row in cursor.fetchall()}


def load_cuisines(cursor, df) -> dict:
    names = df["preferred_cuisine"].dropna().unique().tolist()
    cursor.executemany(
        "INSERT IGNORE INTO cuisines (cuisine_name) VALUES (%s)",
        [(n,) for n in names],
    )
    cursor.execute("SELECT cuisine_id, cuisine_name FROM cuisines")
    return {row[1]: row[0] for row in cursor.fetchall()}


def load_routes(cursor, df) -> dict:
    route_df = (
        df[["route_taken", "route_type", "small_route", "bike_friendly_route"]]
        .dropna(subset=["route_taken"])
        .drop_duplicates(subset=["route_taken"])
    )
    rows = [
        (r.route_taken, r.route_type, bool(r.small_route), bool(r.bike_friendly_route))
        for r in route_df.itertuples(index=False)
    ]
    cursor.executemany(
        """INSERT IGNORE INTO routes (route_name, route_type, small_route, bike_friendly)
           VALUES (%s, %s, %s, %s)""",
        rows,
    )
    cursor.execute("SELECT route_id, route_name FROM routes")
    return {row[1]: row[0] for row in cursor.fetchall()}


def load_restaurants(cursor, df):
    ids = df["restaurant_id"].dropna().unique().tolist()
    cursor.executemany(
        "INSERT IGNORE INTO restaurants (restaurant_id) VALUES (%s)",
        [(int(i),) for i in ids],
    )


def load_customers(cursor, df, loc_map, cui_map):
    cust_df = (
        df[["customer_id", "age", "gender", "location",
            "order_history", "order_frequency", "loyalty_program", "preferred_cuisine"]]
        .drop_duplicates(subset=["customer_id"])
    )
    rows = [
        (
            r.customer_id,
            None if pd.isna(r.age) else int(r.age),
            r.gender if pd.notna(r.gender) else None,
            loc_map.get(r.location),
            None if pd.isna(r.order_history) else int(r.order_history),
            r.order_frequency if pd.notna(r.order_frequency) else None,
            bool(r.loyalty_program),
            cui_map.get(r.preferred_cuisine),
        )
        for r in cust_df.itertuples(index=False)
    ]
    n = executemany_batch(
        cursor,
        """INSERT IGNORE INTO customers
           (customer_id, age, gender, location_id, order_history,
            order_frequency, loyalty_program, cuisine_id)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
        rows,
    )
    print(f"[ETL] Customers inserted: {n}")


def load_orders(cursor, df):
    rows = [
        (
            r.order_id,
            r.customer_id,
            int(r.restaurant_id),
            None if pd.isnull(r.order_time) else r.order_time.to_pydatetime(),
            None if pd.isna(r.order_value) else float(r.order_value),
            r.delivery_method if pd.notna(r.delivery_method) else None,
        )
        for r in df.itertuples(index=False)
    ]
    n = executemany_batch(
        cursor,
        """INSERT IGNORE INTO orders
           (order_id, customer_id, restaurant_id, order_time, order_value, delivery_method)
           VALUES (%s,%s,%s,%s,%s,%s)""",
        rows,
    )
    print(f"[ETL] Orders inserted: {n}")


def load_order_items(cursor, df):
    rows = [
        (r.order_id, r.food_item if pd.notna(r.food_item) else None)
        for r in df.itertuples(index=False)
        if pd.notna(getattr(r, "food_item", None))
    ]
    n = executemany_batch(
        cursor,
        "INSERT INTO order_items (order_id, food_item) VALUES (%s,%s)",
        rows,
    )
    print(f"[ETL] Order items inserted: {n}")


def load_deliveries(cursor, df, route_map):
    rows = []
    for r in df.itertuples(index=False):
        rows.append((
            r.order_id,
            None if pd.isnull(r.delivery_time) else r.delivery_time.to_pydatetime(),
            None if pd.isna(r.delivery_distance) else float(r.delivery_distance),
            None if pd.isna(r.delivery_delay)    else float(r.delivery_delay),
            r.traffic_condition  if pd.notna(r.traffic_condition)  else None,
            r.weather_condition  if pd.notna(r.weather_condition)  else None,
            route_map.get(r.route_taken),
            None if pd.isna(r.route_efficiency) else float(r.route_efficiency),
            bool(r.traffic_avoidance),
        ))
    n = executemany_batch(
        cursor,
        """INSERT IGNORE INTO deliveries
           (order_id, delivery_time, delivery_distance, delivery_delay,
            traffic_condition, weather_condition, route_id,
            route_efficiency, traffic_avoidance)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
        rows,
    )
    print(f"[ETL] Deliveries inserted: {n}")


def load_feedback(cursor, df):
    rows = [
        (
            r.order_id,
            None if pd.isna(r.customer_rating)       else int(r.customer_rating),
            None if pd.isna(r.customer_satisfaction)  else int(r.customer_satisfaction),
            r.food_temperature if pd.notna(r.food_temperature) else None,
            None if pd.isna(r.food_freshness)         else int(r.food_freshness),
            None if pd.isna(r.packaging_quality)      else int(r.packaging_quality),
            r.food_condition   if pd.notna(r.food_condition)   else None,
        )
        for r in df.itertuples(index=False)
    ]
    n = executemany_batch(
        cursor,
        """INSERT IGNORE INTO feedback
           (order_id, customer_rating, customer_satisfaction, food_temperature,
            food_freshness, packaging_quality, food_condition)
           VALUES (%s,%s,%s,%s,%s,%s,%s)""",
        rows,
    )
    print(f"[ETL] Feedback inserted: {n}")


# ── Main ──────────────────────────────────────────────────────────────────────

def run(csv_path: str):
    df = pd.read_csv(csv_path)
    df = clean(df)

    conn = get_connection()
    cur  = conn.cursor()

    try:
        print("[ETL] Loading lookup tables …")
        loc_map   = load_locations(cur, df)
        cui_map   = load_cuisines(cur, df)
        route_map = load_routes(cur, df)
        load_restaurants(cur, df)

        print("[ETL] Loading dimension tables …")
        load_customers(cur, df, loc_map, cui_map)

        print("[ETL] Loading fact tables …")
        load_orders(cur, df)
        load_order_items(cur, df)
        load_deliveries(cur, df, route_map)
        load_feedback(cur, df)

        conn.commit()
        print("[ETL] ✅  All data committed.")
    except Exception as e:
        conn.rollback()
        raise RuntimeError(f"[ETL] ❌  Rolled back due to: {e}") from e
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Load food-delivery CSV into MySQL")
    parser.add_argument("--csv", default=DEFAULT_CSV, help="Path to the CSV file")
    args = parser.parse_args()
    run(args.csv)
