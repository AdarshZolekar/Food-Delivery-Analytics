# System Architecture

## Overview

SwiftEats uses a single PostgreSQL instance serving both transactional (OLTP) and analytical (OLAP) workloads — the standard pattern for a growth-stage startup before a dedicated data warehouse is introduced.

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│  Source Systems (Application Layer)                        │
│  Customer App  │  Restaurant Portal  │  Partner App        │
│  Support CRM   │  Payment Gateway    │  Admin Panel        │
└──────────────────────────────┬─────────────────────────────┘
                               │ writes (ACID transactions)
┌──────────────────────────────▼─────────────────────────────┐
│  OLTP Core — PostgreSQL 16                                  │
│                                                            │
│  Orders    Order_Items    Deliveries    Customers           │
│  Restaurants   Partners   Reviews   Payments   Tickets      │
│  Promotions   Zones   Cities   Menu_Items                   │
└──────────────────────────────┬─────────────────────────────┘
                               │ triggers + scheduled views
┌──────────────────────────────▼─────────────────────────────┐
│  Analytics Layer                                            │
│                                                            │
│  mv_daily_kpi        mv_restaurant_performance             │
│  mv_hourly_demand    mv_partner_performance                 │
│  mv_customer_rfm     v_order_detail (live)                  │
└──────────────────────────────┬─────────────────────────────┘
                               │
         ┌─────────────────────┼────────────────────┐
         ▼                     ▼                    ▼
   Power BI Dashboards   Jupyter Notebooks    Ad-hoc SQL
```

---

## Key Design Decisions

### Generated Columns
`order_items.item_total = quantity × unit_price` and `deliveries.sla_breached = actual_time_mins > 45` are GENERATED ALWAYS AS columns. This eliminates application-layer computation drift and makes the flag queryable without recalculation.

### Trigger-Driven Denormalization
`restaurants.rating`, `restaurants.total_orders`, `customers.total_spent`, `delivery_partners.total_deliveries` are denormalized aggregates updated by triggers. This avoids expensive COUNT/AVG joins on every dashboard page load.

### UNLOGGED vs LOGGED Tables
All tables are LOGGED for durability. For a future analytics-only staging schema, UNLOGGED tables would be appropriate.

### Materialized View Refresh Strategy
Views refresh nightly via `CALL refresh_all_views()`. For `mv_customer_rfm` (expensive), weekly is sufficient. Production would use `pg_cron` for scheduling.

### Partitioning
`orders` is partitioned by `order_date` (monthly). With 1M orders over 3 years, this reduces scanned rows by 97% for single-month queries.

---

## Scalability Path

| Scale | Change |
|-------|--------|
| 10× orders | Partition `deliveries` and `order_status_history` by month |
| 100× reads | Add read replica; route analytics queries there |
| 1000× data | Migrate aggregations to Snowflake/BigQuery with dbt models |
| Multi-city | Row-level security by city_id for regional dashboards |
