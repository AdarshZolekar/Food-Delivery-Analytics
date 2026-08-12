# Executive Dashboard Specification

## Purpose
Single-page C-suite view answering: **Is the platform growing profitably?**

## Data Sources
- `mv_daily_kpi` — daily platform KPIs
- `mv_restaurant_performance` — restaurant health
- `mv_customer_rfm` — customer segmentation

## Metrics Tile Layout

```
Row 1 (6 tiles):
  ┌─────────┬─────────┬──────────────┬────────────┬──────────┬──────────┐
  │ ₹4.2M   │ ₹840K   │ 18,420       │ 12,340     │ ₹228     │ 20.0%    │
  │ MTD GMV │ Plat Rev│ MTD Orders   │ Active Cust│ AOV      │ Take Rate│
  │ ↑12.3%  │ ↑9.1%   │ ↑11.5%      │ ↑18.2%     │ ↑0.7%    │ Stable   │
  └─────────┴─────────┴──────────────┴────────────┴──────────┴──────────┘

Row 2 (3 panels):
  ┌──────────────────────┬───────────────┬──────────────────────────────┐
  │ 12-Month GMV Trend   │ City Revenue  │ Customer Growth              │
  │ Line + 3M MA         │ Filled Map    │ New vs Returning (Stacked)   │
  └──────────────────────┴───────────────┴──────────────────────────────┘

Row 3 (2 panels):
  ┌──────────────────────────────────────┬───────────────────────────────┐
  │ Top 10 Restaurants by Revenue        │ Cancellation Rate Trend       │
  │ Horizontal bar with YoY comparison   │ Line with 5% threshold line   │
  └──────────────────────────────────────┴───────────────────────────────┘
```

## Key Business Questions Answered

1. Is GMV growing month-over-month? → MoM growth tile + trend line
2. Are we keeping customers? → New vs returning split
3. Which cities are driving growth? → City revenue map
4. What is the platform margin? → Take rate tile
5. Is operational quality improving? → Cancellation rate trend
