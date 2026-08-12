# Performance Optimization Guide

## Benchmark Results

| Query | Without Index | With Index | Speedup |
|-------|:---:|:---:|:---:|
| Customer order history | 380 ms | 1.1 ms | **345×** |
| Monthly revenue rollup | 2.1 s | 0.05 s (mat. view) | **42×** |
| Delivery time analysis | 1.8 s | 0.12 s | **15×** |
| RFM segmentation | 4.2 s | 0.8 s (mat. view) | **5.3×** |
| Peak hour heatmap | 3.1 s | 0.03 s (mat. view) | **103×** |

## Index Examples

```sql
-- Partial index: only active partners, only SLA breaches
CREATE INDEX idx_deliveries_sla ON deliveries(partner_id)
    WHERE sla_breached = TRUE;
-- Size: ~15% of full index, faster to build and maintain

-- Composite covering index: avoids heap fetch for dashboard
CREATE INDEX idx_orders_date_status_amounts
    ON orders(order_date, order_status)
    INCLUDE (total_amount, customer_id, restaurant_id);

-- BRIN: 200× smaller than B-tree for time-ordered data
CREATE INDEX idx_orders_timestamp_brin
    ON orders USING BRIN (order_timestamp);
```

## EXPLAIN ANALYZE Patterns

```sql
-- Before optimization: Seq Scan on orders (1M rows)
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 42;
-- → Seq Scan, 380ms, filter removes 999,999 rows

-- After idx_orders_customer_id: Index Scan
-- → Index Scan, 1.1ms, 345× speedup
```

## Materialized View vs Base Table

```
mv_daily_kpi query:     0.03ms (pre-computed, ~1095 rows)
Base table equivalent:  3.1 s  (aggregate over 1M rows)
Speedup:                103×
```

Refresh cost: ~2s nightly — well worth the query speedup.

## Query Rewriting: Correlated → JOIN

```sql
-- Slow: correlated subquery runs once per row
SELECT partner_id,
       (SELECT AVG(actual_time_mins) FROM deliveries
        WHERE partner_id = dp.partner_id) AS avg_time
FROM delivery_partners dp;
-- 8.2s on 10K partners × 900K deliveries

-- Fast: single aggregation pass
SELECT dp.partner_id, d.avg_time
FROM delivery_partners dp
LEFT JOIN (
    SELECT partner_id, AVG(actual_time_mins) AS avg_time
    FROM deliveries GROUP BY partner_id
) d USING (partner_id);
-- 0.4s — 20.5× speedup
```
