# Operational Dashboard Specification

## Purpose
Real-time operational health for City Managers and the Ops team.

## Refresh Cadence
- Order funnel: near-real-time (DirectQuery on `v_order_detail`)
- Delivery metrics: hourly refresh from `mv_partner_performance`
- Zone risk: daily from `mv_hourly_demand`

## Page 1: Live Order Monitoring

```
┌─────────────────────────────────────────────────────────────────┐
│ [Active Orders] [Unassigned] [Avg Wait] [Partners Online]       │
├──────────────────────────────┬──────────────────────────────────┤
│ Orders by Status (Donut)     │ Unassigned Orders by Zone (Bar)  │
│ Placed/Confirmed/Preparing/  │ Sorted by wait time              │
│ OnTheWay/Delivered/Cancelled │                                  │
├──────────────────────────────┴──────────────────────────────────┤
│ Order Stream Table (refresh every 60s)                          │
│ order_id | restaurant | customer | status | time_elapsed        │
└─────────────────────────────────────────────────────────────────┘
```

## Page 2: Delivery Heatmap

- **X-axis:** Hour of day (0–23)
- **Y-axis:** Day of week (Mon–Sun)
- **Color:** Demand index (Green → Amber → Red)
- **Tooltip:** Orders, avg delivery time, SLA breach %

**Business use:** Staff partner supply proactively before peaks.

## Page 3: Zone Risk

| Visual | Metric | Alert |
|--------|--------|-------|
| Map (color coded) | SLA breach % per zone | Red > 15% |
| Bar chart | Avg delivery time vs target | Red > target × 1.3 |
| Table | Active partners per zone | Flag if < 5 available |

## Page 4: Partner Performance

- Top 20 and bottom 20 partners by on-time rate
- Vehicle type distribution by city
- Utilisation: deliveries per partner per day histogram
- Earnings distribution (box plot by vehicle type)
