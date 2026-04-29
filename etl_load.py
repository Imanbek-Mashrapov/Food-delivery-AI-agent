"""
ETL: Food Delivery dataset → MySQL
====================================

Reads the raw CSV, cleans it, and inserts everything into the
`food_delivery` database created by 01_schema.sql.

USAGE:
    1. Run 01_schema.sql in MySQL Workbench first.
    2. Copy .env.example to .env and fill in your credentials.
    3. python etl_load.py

The script is idempotent: it uses INSERT IGNORE everywhere, so you
can re-run it safely. It also wraps each table load in a transaction.
"""

import os
import sys
from pathlib import Path

import pandas as pd
import mysql.connector
from mysql.connector import Error
from dotenv import load_dotenv

# ── Configuration ─────────────────────────────────────────────
load_dotenv()

CSV_PATH = Path(__file__).parent / "food_delivery_dataset.csv"

DB_CONFIG = {
    "host":     os.getenv("DB_HOST", "localhost"),
    "port":     int(os.getenv("DB_PORT", "3306")),
    "user":     os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "food_delivery"),
}


# ── Helpers ───────────────────────────────────────────────────
def to_bool(value) -> bool:
    """Map any 'truthy' representation to a real boolean."""
    if isinstance(value, bool):
        return value
    if pd.isna(value):
        return False
    s = str(value).strip().lower()
    return s in ("yes", "true", "1", "y", "t")


def clean_dataset(df: pd.DataFrame) -> pd.DataFrame:
    """All cleaning happens here, in one place."""
    print(f"[clean] starting with {len(df):,} rows")

    # 1. strip whitespace from string columns
    for col in df.select_dtypes(include="object").columns:
        df[col] = df[col].astype(str).str.strip()

    # 2. parse datetime columns; bad values → NaT (will become NULL)
    df["order_time"]    = pd.to_datetime(df["order_time"],    errors="coerce")
    df["delivery_time"] = pd.to_datetime(df["delivery_time"], errors="coerce")

    # 3. coerce numeric columns
    df["age"]              = pd.to_numeric(df["age"], errors="coerce").clip(0, 120)
    df["order_value"]      = pd.to_numeric(df["order_value"], errors="coerce").clip(lower=0)
    df["delivery_distance"]= pd.to_numeric(df["delivery_distance"], errors="coerce").clip(lower=0)
    df["delivery_delay"]   = pd.to_numeric(df["delivery_delay"], errors="coerce")
    df["route_efficiency"] = pd.to_numeric(df["route_efficiency"], errors="coerce").clip(0, 1)

    # 4. boolean coercion
    df["loyalty_program"]     = df["loyalty_program"].apply(to_bool)
    df["small_route"]         = df["small_route"].apply(to_bool)
    df["bike_friendly_route"] = df["bike_friendly_route"].apply(to_bool)
    df["traffic_avoidance"]   = df["traffic_avoidance"].apply(to_bool)

    # 5. drop rows missing critical foreign keys
    before = len(df)
    df = df.dropna(subset=["order_id", "customer_id", "restaurant_id", "order_time"])
    print(f"[clean] dropped {before - len(df)} rows with missing critical keys")

    # 6. deduplicate on the natural primary key
    before = len(df)
    df = df.drop_duplicates(subset=["order_id"])
    print(f"[clean] dropped {before - len(df)} duplicate order_ids")

    print(f"[clean] finished with {len(df):,} rows")
    return df


def batch_insert(cursor, sql: str, rows: list, label: str, batch_size: int = 1000):
    """Insert rows in batches and report progress."""
    total = len(rows)
    if total == 0:
        print(f"  [{label}] nothing to insert")
        return
    for i in range(0, total, batch_size):
        cursor.executemany(sql, rows[i:i + batch_size])
    print(f"  [{label}] inserted {total:,} rows")


# ── Main ETL ──────────────────────────────────────────────────
def main():
    if not CSV_PATH.exists():
        sys.exit(f"❌ CSV not found at {CSV_PATH}")

    print("=" * 60)
    print("FOOD DELIVERY ETL")
    print("=" * 60)

    # 1. load + clean
    df = pd.read_csv(CSV_PATH)
    df = clean_dataset(df)

    # 2. connect to MySQL
    print(f"\n[db] connecting to {DB_CONFIG['user']}@{DB_CONFIG['host']}:{DB_CONFIG['port']} / {DB_CONFIG['database']}")
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
    except Error as e:
        sys.exit(f"❌ connection failed: {e}")

    cursor = conn.cursor()

    try:
        # ── 3. lookup tables ───────────────────────────────
        print("\n[load] lookup tables")

        cities = sorted(df["location"].dropna().unique().tolist())
        batch_insert(cursor,
                     "INSERT IGNORE INTO locations (city) VALUES (%s)",
                     [(c,) for c in cities],
                     "locations")

        cuisines = sorted(df["preferred_cuisine"].dropna().unique().tolist())
        batch_insert(cursor,
                     "INSERT IGNORE INTO cuisines (cuisine_name) VALUES (%s)",
                     [(c,) for c in cuisines],
                     "cuisines")

        # routes — derived (one row per unique route_taken)
        route_rows = (
            df[["route_taken", "route_type", "small_route", "bike_friendly_route"]]
            .drop_duplicates(subset=["route_taken"])
            .sort_values("route_taken")
            .values.tolist()
        )
        batch_insert(cursor,
                     """INSERT IGNORE INTO routes
                        (route_name, route_type, small_route, bike_friendly)
                        VALUES (%s, %s, %s, %s)""",
                     route_rows,
                     "routes")

        # ── 4. lookup id mappings ───────────────────────────
        cursor.execute("SELECT location_id, city FROM locations")
        loc_map = {city: lid for lid, city in cursor.fetchall()}

        cursor.execute("SELECT cuisine_id, cuisine_name FROM cuisines")
        cui_map = {name: cid for cid, name in cursor.fetchall()}

        cursor.execute("SELECT route_id, route_name FROM routes")
        rou_map = {name: rid for rid, name in cursor.fetchall()}

        # ── 5. dimension tables ─────────────────────────────
        print("\n[load] dimension tables")

        restaurants = sorted(df["restaurant_id"].dropna().unique().tolist())
        batch_insert(cursor,
                     "INSERT IGNORE INTO restaurants (restaurant_id) VALUES (%s)",
                     [(int(r),) for r in restaurants],
                     "restaurants")

        # one row per unique customer
        customer_rows = (
            df.drop_duplicates(subset=["customer_id"])
              .apply(lambda r: (
                  r["customer_id"],
                  int(r["age"]) if pd.notna(r["age"]) else None,
                  r["gender"],
                  loc_map.get(r["location"]),
                  int(r["order_history"]) if pd.notna(r["order_history"]) else None,
                  r["order_frequency"],
                  bool(r["loyalty_program"]),
                  cui_map.get(r["preferred_cuisine"]),
              ), axis=1)
              .tolist()
        )
        batch_insert(cursor,
                     """INSERT IGNORE INTO customers
                        (customer_id, age, gender, location_id, order_history,
                         order_frequency, loyalty_program, cuisine_id)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                     customer_rows,
                     "customers")

        # ── 6. fact tables ──────────────────────────────────
        print("\n[load] fact tables")

        order_rows = df.apply(lambda r: (
            r["order_id"],
            r["customer_id"],
            int(r["restaurant_id"]),
            r["order_time"].to_pydatetime() if pd.notna(r["order_time"]) else None,
            float(r["order_value"]) if pd.notna(r["order_value"]) else 0.0,
            r["delivery_method"],
        ), axis=1).tolist()
        batch_insert(cursor,
                     """INSERT IGNORE INTO orders
                        (order_id, customer_id, restaurant_id,
                         order_time, order_value, delivery_method)
                        VALUES (%s, %s, %s, %s, %s, %s)""",
                     order_rows,
                     "orders")

        item_rows = df[["order_id", "food_item"]].values.tolist()
        batch_insert(cursor,
                     "INSERT IGNORE INTO order_items (order_id, food_item) VALUES (%s, %s)",
                     [(o, f) for o, f in item_rows],
                     "order_items")

        delivery_rows = df.apply(lambda r: (
            r["order_id"],
            r["delivery_time"].to_pydatetime() if pd.notna(r["delivery_time"]) else None,
            float(r["delivery_distance"]) if pd.notna(r["delivery_distance"]) else None,
            float(r["delivery_delay"])    if pd.notna(r["delivery_delay"])    else None,
            r["traffic_condition"],
            r["weather_condition"],
            rou_map.get(r["route_taken"]),
            float(r["route_efficiency"]) if pd.notna(r["route_efficiency"]) else None,
            bool(r["traffic_avoidance"]),
        ), axis=1).tolist()
        batch_insert(cursor,
                     """INSERT IGNORE INTO deliveries
                        (order_id, delivery_time, delivery_distance, delivery_delay,
                         traffic_condition, weather_condition, route_id,
                         route_efficiency, traffic_avoidance)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                     delivery_rows,
                     "deliveries")

        feedback_rows = df.apply(lambda r: (
            r["order_id"],
            int(r["customer_rating"])       if pd.notna(r["customer_rating"])       else None,
            int(r["customer_satisfaction"]) if pd.notna(r["customer_satisfaction"]) else None,
            r["food_temperature"],
            int(r["food_freshness"])    if pd.notna(r["food_freshness"])    else None,
            int(r["packaging_quality"]) if pd.notna(r["packaging_quality"]) else None,
            r["food_condition"],
        ), axis=1).tolist()
        batch_insert(cursor,
                     """INSERT IGNORE INTO feedback
                        (order_id, customer_rating, customer_satisfaction,
                         food_temperature, food_freshness, packaging_quality,
                         food_condition)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                     feedback_rows,
                     "feedback")

        # commit everything
        conn.commit()
        print("\n✅ all data committed")

        # ── 7. final row counts ─────────────────────────────
        print("\n[verify] final row counts")
        for tbl in ["locations", "cuisines", "routes", "restaurants",
                    "customers", "orders", "order_items", "deliveries", "feedback"]:
            cursor.execute(f"SELECT COUNT(*) FROM {tbl}")
            (cnt,) = cursor.fetchone()
            print(f"  {tbl:<14} {cnt:>8,}")

    except Error as e:
        conn.rollback()
        sys.exit(f"\n❌ ETL failed, rolled back: {e}")
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()
