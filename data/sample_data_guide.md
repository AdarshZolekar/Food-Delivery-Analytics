# Sample Data Guide

## Generation

Run `python data/generate_data.py` to produce all CSV files in `data/generated/`.

| File | Rows | Notes |
|------|------|-------|
| `restaurants.csv` | 5,000 | Restaurant profiles across 10 cities |
| `menu_items.csv` | ~150,000 | 20–40 items per restaurant |
| `customers.csv` | 100,000 | With power-law order frequency |
| `delivery_partners.csv` | 10,000 | Zone-assigned partners |
| `orders_YYYY_MM.csv` | ~1M total | Monthly partitioned files |
| `order_items.csv` | ~2.5M | Avg 2.5 items per order |
| `deliveries.csv` | ~900K | Excludes cancelled orders |
| `payments.csv` | ~1M | One payment per order |

## Temporal Patterns Embedded

- **Lunch peak:** 12:00–14:00 — 3.5–3.8× baseline order rate
- **Dinner peak:** 19:00–22:00 — 4.0–5.0× baseline order rate
- **Weekend boost:** Saturday/Sunday orders 30% higher than weekdays
- **Late night:** 23:00–01:00 — 1.5× baseline (urban zones only)
- **Order status:** 78% Delivered, 15% Cancelled, 7% other states
- **Customer distribution:** Power law — top 20% customers place 60% of orders

## Loading Order

```bash
# 1. Schema and seeds
psql -d food_delivery -f schema/create_database.sql
psql -d food_delivery -f schema/create_tables.sql
psql -d food_delivery -f schema/constraints.sql
psql -d food_delivery -f data/seed_data.sql

# 2. Generated data (Python loader handles FK ordering)
python scripts/load_data.py

# 3. Indexes, views, triggers (after data for speed)
psql -d food_delivery -f schema/indexes.sql
psql -d food_delivery -f schema/views.sql
psql -d food_delivery -f schema/triggers.sql

# 4. Procedures
psql -d food_delivery -f procedures/order_management.sql
psql -d food_delivery -f procedures/delivery_management.sql
psql -d food_delivery -f procedures/customer_operations.sql
psql -d food_delivery -f procedures/analytics_procedures.sql
```
