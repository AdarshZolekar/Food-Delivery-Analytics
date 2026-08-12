# Database Design

## Normalization

All tables are in Third Normal Form (3NF):
- Addresses stored separately (`customer_addresses`)
- Cities and zones are reference tables, not embedded strings
- Menu items reference restaurants via FK, not via name embedding

## Key Design Decisions

### `order_date` as GENERATED Column
```sql
order_date DATE GENERATED ALWAYS AS (order_timestamp::date) STORED
```
Allows fast date-based filtering and partition pruning without a function call at query time.

### SCD Approach for Pricing
`order_items.unit_price` captures the price **at time of sale**. If a restaurant raises prices later, historical orders remain accurate.

### Soft Deletes
`is_active` flags on `restaurants`, `customers`, and `delivery_partners` enable logical deletion while preserving historical order data and foreign key integrity.

### Audit Trail
`order_status_history` is append-only and populated by triggers. This provides a complete lifecycle audit for every order without modifying the orders table itself.

## Table Row Estimates

| Table | Rows | Growth Rate |
|-------|------|-------------|
| orders | 1,000,000 | ~30K/month |
| order_items | 2,500,000 | ~75K/month |
| deliveries | 900,000 | ~27K/month |
| order_status_history | 4,000,000 | ~120K/month |
| customers | 100,000 | ~3K/month |
| restaurants | 5,000 | ~50/month |
| delivery_partners | 10,000 | ~100/month |
| reviews | 750,000 | ~22K/month |

## Index Strategy Summary

25+ indexes across 15 tables. Key patterns:
- **BRIN** on `order_timestamp` — tiny index for large time-series scans
- **Partial** on `delivery_partners(zone_id) WHERE is_active = TRUE` — excludes churned partners
- **Partial** on `deliveries(partner_id) WHERE sla_breached = TRUE` — fast SLA alert queries
- **GIN trigram** on `restaurant_name` — fuzzy search support
- **Composite covering** on `orders(order_date, order_status) INCLUDE (total_amount, ...)` — avoids heap fetch for dashboard queries
