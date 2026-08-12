"""
Run all analytics queries and export results to CSV/JSON.

Usage:
    python scripts/run_analytics.py
    python scripts/run_analytics.py --query peak_hours
    python scripts/run_analytics.py --output reports/
"""

import argparse
import json
import os
import time
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv
import pandas as pd
from sqlalchemy import create_engine, text

load_dotenv()


def get_engine():
    return create_engine(
        f"postgresql://{os.getenv('DB_USER','food_user')}:{os.getenv('DB_PASSWORD','')}"
        f"@{os.getenv('DB_HOST','localhost')}:{os.getenv('DB_PORT','5432')}"
        f"/{os.getenv('DB_NAME','food_delivery')}"
    )


QUERIES = {
    "platform_kpis": """
        SELECT
            COUNT(*) FILTER (WHERE order_status='Delivered')    AS delivered_orders,
            COUNT(*) FILTER (WHERE order_status='Cancelled')    AS cancelled_orders,
            ROUND(SUM(total_amount) FILTER (WHERE order_status='Delivered')::numeric,2) AS gmv,
            ROUND(AVG(total_amount) FILTER (WHERE order_status='Delivered')::numeric,2) AS aov,
            COUNT(DISTINCT customer_id)                         AS unique_customers,
            COUNT(DISTINCT restaurant_id)                       AS unique_restaurants
        FROM orders
        WHERE order_date >= CURRENT_DATE - 30
    """,

    "peak_hours": """
        SELECT day_of_week, day_name, hour_of_day,
               order_count, demand_index,
               ROUND(avg_order_value::numeric, 2) AS avg_order_value
        FROM mv_hourly_demand
        ORDER BY demand_index DESC
        LIMIT 50
    """,

    "top_restaurants": """
        SELECT restaurant_name, cuisine_type, city_name,
               total_orders, gross_revenue, avg_order_value,
               avg_food_rating, revenue_rank
        FROM mv_restaurant_performance
        WHERE revenue_rank <= 20
        ORDER BY revenue_rank
    """,

    "rfm_segments": """
        SELECT rfm_segment,
               COUNT(*) AS customers,
               ROUND(AVG(monetary)::numeric,2) AS avg_ltv,
               ROUND(SUM(monetary)::numeric,2) AS total_revenue
        FROM mv_customer_rfm
        GROUP BY rfm_segment
        ORDER BY avg_ltv DESC
    """,

    "delivery_performance": """
        SELECT zone_name, city_name, total_deliveries,
               avg_delivery_time, on_time_rate_pct, sla_breaches
        FROM mv_partner_performance
        GROUP BY zone_name, city_name, total_deliveries,
                 avg_delivery_time, on_time_rate_pct, sla_breaches
        ORDER BY total_deliveries DESC
        LIMIT 30
    """,

    "churn_segments": """
        SELECT rfm_segment AS churn_segment,
               COUNT(*) AS customers,
               ROUND(AVG(recency_days)::numeric,0) AS avg_days_inactive,
               ROUND(AVG(monetary)::numeric,2) AS avg_ltv
        FROM mv_customer_rfm
        WHERE rfm_segment IN ('At Risk','Hibernating','Lost')
        GROUP BY rfm_segment
        ORDER BY avg_ltv DESC
    """,
}


def run_all(engine, output_dir: str, queries: list[str] | None = None):
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    report = {"generated_at": datetime.now().isoformat(), "results": {}}

    selected = queries or list(QUERIES.keys())
    print(f"\n{'─'*50}")
    print(f" Running {len(selected)} analytics queries")
    print(f"{'─'*50}")

    with engine.connect() as conn:
        for name in selected:
            if name not in QUERIES:
                print(f"  ⚠  Unknown query: {name}")
                continue
            t = time.time()
            try:
                df = pd.read_sql(text(QUERIES[name]), conn)
                out_path = Path(output_dir) / f"{name}.csv"
                df.to_csv(out_path, index=False)
                report["results"][name] = {
                    "rows": len(df),
                    "duration_ms": round((time.time() - t) * 1000, 1),
                    "output": str(out_path),
                }
                print(f"  ✓ {name:<30} {len(df):>6} rows  ({report['results'][name]['duration_ms']} ms)")
            except Exception as e:
                print(f"  ✗ {name}: {e}")
                report["results"][name] = {"error": str(e)}

    report_path = Path(output_dir) / "analytics_report.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\n  Report saved: {report_path}")


def main():
    parser = argparse.ArgumentParser(description="SwiftEats analytics runner")
    parser.add_argument("--query", nargs="+", choices=list(QUERIES.keys()),
                        help="Specific queries to run (default: all)")
    parser.add_argument("--output", default="reports", help="Output directory")
    args = parser.parse_args()

    engine = get_engine()
    run_all(engine, args.output, args.query)


if __name__ == "__main__":
    main()
