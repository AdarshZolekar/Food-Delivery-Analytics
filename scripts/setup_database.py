"""
Database setup script for the SwiftEats food delivery analytics platform.
Creates schemas, runs DDL files in order, and validates the result.

Usage:
    python scripts/setup_database.py
    python scripts/setup_database.py --drop-existing
"""

import argparse
import os
import sys
import time
from pathlib import Path
from dotenv import load_dotenv
import psycopg2
from psycopg2 import sql

load_dotenv()


def get_conn(dbname: str | None = None):
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=dbname or os.getenv("DB_NAME", "food_delivery"),
        user=os.getenv("DB_USER", "food_user"),
        password=os.getenv("DB_PASSWORD", ""),
    )


def run_file(conn, path: str, label: str) -> None:
    t = time.time()
    content = Path(path).read_text(encoding="utf-8")
    with conn.cursor() as cur:
        cur.execute(content)
    conn.commit()
    print(f"  ✓ {label:<45} ({time.time()-t:.1f}s)")


def ensure_database():
    db_name = os.getenv("DB_NAME", "food_delivery")
    try:
        conn = get_conn("postgres")
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
            if not cur.fetchone():
                cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db_name)))
                print(f"  ✓ Database '{db_name}' created")
            else:
                print(f"  ✓ Database '{db_name}' already exists")
        conn.close()
    except psycopg2.OperationalError as e:
        print(f"  ⚠  Could not auto-create database: {e}")


def main(drop_existing: bool = False):
    print("\n" + "=" * 55)
    print(" SwiftEats — Database Setup")
    print("=" * 55)

    print("\n[1] Ensuring database exists...")
    ensure_database()

    print("\n[2] Connecting...")
    try:
        conn = get_conn()
        print(f"  ✓ Connected to {os.getenv('DB_NAME', 'food_delivery')}")
    except psycopg2.OperationalError as e:
        print(f"  ✗ {e}")
        sys.exit(1)

    if drop_existing:
        print("\n[3] Dropping existing objects...")
        with conn.cursor() as cur:
            cur.execute("""
                DROP TABLE IF EXISTS order_status_history, support_tickets, reviews,
                    payments, deliveries, order_items, orders, promotions,
                    customer_addresses, customers, delivery_partners,
                    menu_items, menu_categories, restaurants, zones, cities CASCADE;
                DROP VIEW IF EXISTS v_order_detail CASCADE;
                DROP MATERIALIZED VIEW IF EXISTS mv_daily_kpi, mv_restaurant_performance,
                    mv_hourly_demand, mv_partner_performance, mv_customer_rfm CASCADE;
            """)
        conn.commit()
        print("  ✓ Existing objects dropped")

    print("\n[4] Creating schema objects...")
    ddl_files = [
        ("schema/create_database.sql",  "Extensions + roles"),
        ("schema/create_tables.sql",    "15 core tables"),
        ("schema/constraints.sql",      "Business constraints"),
        ("data/seed_data.sql",          "Cities, zones, promotions"),
        ("schema/indexes.sql",          "30+ performance indexes"),
        ("schema/views.sql",            "Views + materialized views"),
        ("schema/triggers.sql",         "7 business triggers"),
        ("procedures/order_management.sql",     "Order procedures"),
        ("procedures/delivery_management.sql",  "Delivery procedures"),
        ("procedures/customer_operations.sql",  "Customer procedures"),
        ("procedures/analytics_procedures.sql", "Analytics functions"),
    ]
    for fpath, label in ddl_files:
        if Path(fpath).exists():
            try:
                run_file(conn, fpath, label)
            except psycopg2.Error as e:
                print(f"  ⚠  {label}: {e.pgerror or str(e)[:80]}")
                conn.rollback()
        else:
            print(f"  ⚠  Not found: {fpath}")

    print("\n[5] Verification...")
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
        tables = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM cities")
        cities = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM zones")
        zones = cur.fetchone()[0]
    print(f"  ✓ Tables: {tables}  |  Cities: {cities}  |  Zones: {zones}")
    conn.close()

    print("\n" + "=" * 55)
    print(" Setup complete! Next: python data/generate_data.py")
    print("=" * 55 + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--drop-existing", action="store_true")
    args = parser.parse_args()
    main(drop_existing=args.drop_existing)
