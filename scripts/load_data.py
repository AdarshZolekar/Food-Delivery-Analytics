"""
Bulk-loads generated CSV files into PostgreSQL using COPY FROM STDIN.
Expected 11× faster than INSERT-based loading.

Usage:
    python scripts/load_data.py
    python scripts/load_data.py --data-dir data/generated
"""

import argparse
import glob
import io
import os
import time
from pathlib import Path
from dotenv import load_dotenv
import pandas as pd
import psycopg2
from tqdm import tqdm

load_dotenv()


def get_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "food_delivery"),
        user=os.getenv("DB_USER", "food_user"),
        password=os.getenv("DB_PASSWORD", ""),
    )


def copy_df(conn, df: pd.DataFrame, table: str, columns: list[str]) -> int:
    """Load a DataFrame using PostgreSQL COPY (fastest bulk load method)."""
    df_sub = df[columns].fillna("")
    buf = io.StringIO()
    df_sub.to_csv(buf, index=False, header=True)
    buf.seek(0)
    col_str = ", ".join(f'"{c}"' for c in columns)
    with conn.cursor() as cur:
        cur.copy_expert(f"COPY {table} ({col_str}) FROM STDIN WITH CSV HEADER NULL ''", buf)
    conn.commit()
    return len(df)


def load_restaurants(conn, data_dir: str):
    path = Path(data_dir) / "restaurants.csv"
    if not path.exists():
        print("  ⚠  restaurants.csv not found — run data/generate_data.py first")
        return
    df = pd.read_csv(path)
    cols = ['restaurant_id', 'restaurant_name', 'cuisine_type', 'city_id', 'zone_id',
            'owner_name', 'phone', 'email', 'address', 'rating', 'avg_delivery_time_mins',
            'min_order_amount', 'commission_rate', 'is_active', 'is_pure_veg', 'joining_date']
    n = copy_df(conn, df, "restaurants", [c for c in cols if c in df.columns])
    print(f"  ✓ Restaurants:       {n:>10,}")


def load_menu_items(conn, data_dir: str):
    path = Path(data_dir) / "menu_items.csv"
    if not path.exists():
        return
    df = pd.read_csv(path)
    cols = ['item_id', 'restaurant_id', 'category_id', 'item_name',
            'price', 'is_available', 'is_vegetarian', 'calories', 'is_bestseller']
    n = copy_df(conn, df, "menu_items", [c for c in cols if c in df.columns])
    print(f"  ✓ Menu items:        {n:>10,}")


def load_customers(conn, data_dir: str):
    path = Path(data_dir) / "customers.csv"
    if not path.exists():
        return
    df = pd.read_csv(path)
    cols = ['customer_id', 'customer_name', 'email', 'phone', 'city_id',
            'registration_date', 'is_active', 'customer_tier', 'acquisition_channel']
    n = copy_df(conn, df, "customers", [c for c in cols if c in df.columns])
    print(f"  ✓ Customers:         {n:>10,}")


def load_delivery_partners(conn, data_dir: str):
    path = Path(data_dir) / "delivery_partners.csv"
    if not path.exists():
        return
    df = pd.read_csv(path)
    cols = ['partner_id', 'partner_name', 'phone', 'email', 'city_id',
            'zone_id', 'vehicle_type', 'is_active', 'current_status',
            'rating', 'joining_date', 'bg_verification']
    n = copy_df(conn, df, "delivery_partners", [c for c in cols if c in df.columns])
    print(f"  ✓ Delivery partners: {n:>10,}")


def load_orders(conn, data_dir: str):
    order_files = sorted(glob.glob(str(Path(data_dir) / "orders_*.csv")))
    total = 0
    for fpath in tqdm(order_files, desc="  Loading order files"):
        df = pd.read_csv(fpath)
        cols = ['order_id', 'customer_id', 'restaurant_id', 'zone_id',
                'order_timestamp', 'order_status', 'order_channel',
                'subtotal_amount', 'discount_amount', 'delivery_fee',
                'taxes', 'total_amount', 'platform_commission',
                'payment_method', 'cancellation_reason']
        n = copy_df(conn, df, "orders", [c for c in cols if c in df.columns])
        total += n
    print(f"  ✓ Orders:            {total:>10,}")


def load_order_items(conn, data_dir: str):
    path = Path(data_dir) / "order_items.csv"
    if not path.exists():
        return
    # Load in chunks for large files
    total = 0
    chunksize = 100_000
    for chunk in pd.read_csv(path, chunksize=chunksize):
        cols = ['order_id', 'item_id', 'quantity', 'unit_price']
        total += copy_df(conn, chunk, "order_items", [c for c in cols if c in chunk.columns])
    print(f"  ✓ Order items:       {total:>10,}")


def load_deliveries(conn, data_dir: str):
    path = Path(data_dir) / "deliveries.csv"
    if not path.exists():
        return
    total = 0
    for chunk in pd.read_csv(path, chunksize=100_000):
        cols = ['order_id', 'partner_id', 'assigned_at', 'delivered_at',
                'actual_time_mins', 'expected_time_mins', 'distance_km',
                'delivery_fee', 'delivery_status', 'partner_earnings']
        total += copy_df(conn, chunk, "deliveries", [c for c in cols if c in chunk.columns])
    print(f"  ✓ Deliveries:        {total:>10,}")


def load_payments(conn, data_dir: str):
    path = Path(data_dir) / "payments.csv"
    if not path.exists():
        return
    total = 0
    for chunk in pd.read_csv(path, chunksize=100_000):
        cols = ['order_id', 'amount', 'payment_method', 'payment_status',
                'transaction_id', 'payment_timestamp']
        total += copy_df(conn, chunk, "payments", [c for c in cols if c in chunk.columns])
    print(f"  ✓ Payments:          {total:>10,}")


def refresh_views(conn):
    print("  Refreshing materialized views...")
    with conn.cursor() as cur:
        for mv in ['mv_daily_kpi', 'mv_restaurant_performance',
                   'mv_hourly_demand', 'mv_partner_performance']:
            cur.execute(f"REFRESH MATERIALIZED VIEW {mv}")
    conn.commit()
    print("  ✓ Materialized views refreshed")


def main(data_dir: str = "data/generated"):
    print("\n" + "=" * 55)
    print(" SwiftEats — Data Loader")
    print(f" Source: {data_dir}")
    print("=" * 55)

    conn = get_conn()
    start = time.time()

    print("\nLoading reference + master data:")
    load_restaurants(conn, data_dir)
    load_menu_items(conn, data_dir)
    load_customers(conn, data_dir)
    load_delivery_partners(conn, data_dir)

    print("\nLoading transactional data:")
    load_orders(conn, data_dir)
    load_order_items(conn, data_dir)
    load_deliveries(conn, data_dir)
    load_payments(conn, data_dir)

    print("\nPost-load tasks:")
    refresh_views(conn)

    conn.close()
    mins, secs = divmod(int(time.time() - start), 60)
    print(f"\n  Total load time: {mins}m {secs}s")
    print("=" * 55 + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="data/generated")
    args = parser.parse_args()
    main(data_dir=args.data_dir)
