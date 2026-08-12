# Power BI Dashboard Design — SwiftEats

## Connection Setup

```
Source:       PostgreSQL (localhost:5432)
Database:     food_delivery
Schema:       public
Import tables: mv_daily_kpi, mv_restaurant_performance,
               mv_hourly_demand, mv_partner_performance, mv_customer_rfm
DirectQuery:  v_order_detail (for live order monitoring)
Refresh:      Nightly at 03:00 IST
```

---

## Dashboard 1: Executive Overview

**Audience:** CEO, CFO, COO

**KPI Cards (top row):**
- MTD GMV + MoM %
- Platform Revenue + MoM %
- Active Customers + MoM %
- Cancellation Rate % (red if >5%)
- Avg Order Value + MoM %
- Take Rate %

**Visuals:**
```
┌───────────────────────────────────────────────────────────────┐
│  [GMV]  [Rev]  [Customers]  [Cancel%]  [AOV]  [Take Rate]    │
├─────────────────────────────┬─────────────────────────────────┤
│  Monthly GMV Trend          │  Revenue by City (Map)          │
│  [Area + 3M MA line]        │  [Filled India map]             │
├─────────────────────────────┼─────────────────────────────────┤
│  New vs Returning Customers │  Top 10 Restaurants (Bar)       │
│  [Stacked column by month]  │  by Platform Revenue            │
└─────────────────────────────┴─────────────────────────────────┘
```

---

## Dashboard 2: Operations — Delivery Intelligence

**Audience:** VP Operations, City Managers

**KPI Cards:**
- Avg Delivery Time (gauge, target 30 min)
- SLA Breach % (red if >10%)
- On-Time Rate %
- Active Partners Today

**Visuals:**
```
┌───────────────────────────────────────────────────────────────┐
│  Delivery Heatmap (Hour × Day)    │  Zone SLA Risk Map        │
│  [Matrix: color = demand_index]   │  [Scatter: zone vs breach%]│
├───────────────────────────────────┼───────────────────────────┤
│  Partner Performance Leaderboard  │  Cancellation Reasons     │
│  [Table with sparklines]          │  [Donut chart]            │
└───────────────────────────────────┴───────────────────────────┘
```

---

## Dashboard 3: Customer Intelligence

**Audience:** CMO, Growth Team

**Visuals:**
- RFM Segment Distribution (Treemap)
- Cohort Retention Heatmap (Matrix: cohort × month_num, color=retention%)
- Customer LTV Histogram
- Churn Risk Segments (Bar with revenue at risk)
- Acquisition Channel AOV Comparison

---

## Dashboard 4: Restaurant Partner Dashboard

**Audience:** Partner Success Team

**Visuals:**
- Restaurant Health Score Distribution
- Revenue by Cuisine Type (Treemap)
- New Restaurant Onboarding Ramp (avg days to 100 orders)
- Rating Trend (line per restaurant — drillthrough)
- Star vs Struggling Partners (Scatter: rating × orders)

---

## Color System

| Status | Color | Hex |
|--------|-------|-----|
| Positive/Target met | Green | `#27AE60` |
| Warning/Near limit | Amber | `#F39C12` |
| Alert/Breach | Red | `#E74C3C` |
| Primary metric | Blue | `#2E86AB` |
| Secondary | Grey | `#95A5A6` |
| Background | Off-white | `#F8F9FA` |

## DAX Measures Library

```dax
[MTD GMV] =
CALCULATE(SUM(mv_daily_kpi[gross_revenue]),
    DATESMTD(mv_daily_kpi[day]))

[MoM GMV Growth %] =
VAR current = [MTD GMV]
VAR prior   = CALCULATE([MTD GMV], DATEADD(mv_daily_kpi[day], -1, MONTH))
RETURN DIVIDE(current - prior, prior, 0)

[SLA Breach %] =
DIVIDE(
    CALCULATE(COUNT(mv_partner_performance[sla_breaches])),
    CALCULATE(SUM(mv_partner_performance[total_deliveries])),
    0
)

[Demand Index Color] =
SWITCH(TRUE(),
    [demand_index] >= 2.0, "#E74C3C",
    [demand_index] >= 1.5, "#F39C12",
    "#27AE60"
)

[Customer Tier Color] =
SWITCH([customer_tier],
    "Platinum", "#8E44AD",
    "Gold",     "#F39C12",
    "Silver",   "#95A5A6",
    "#CD6155"
)
```
