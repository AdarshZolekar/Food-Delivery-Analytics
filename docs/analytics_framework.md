# Analytics Framework

## Analytical Layers

```
SQL Queries → Materialized Views → Power BI → Executive Decisions
```

## Core Analytics Modules

### 1. Peak Demand Analysis
**Business question:** When should we surge partner supply?

Key output: Hour × Day demand heatmap with demand_index
- demand_index > 2.0 = 2× busier than average → max staffing
- dinner rush (19–22h, weekends) consistently shows index 3.5–5.0

### 2. Customer Retention Science
**Business question:** Which customers are about to churn, and what is their value?

Steps:
1. Cohort assignment: `DATE_TRUNC('month', MIN(order_timestamp))`
2. Retention matrix: month 0 through month 12
3. RFM scoring: NTILE(5) on recency, frequency, monetary
4. Churn segment: days_since_last_order bucketed into Active/Cooling/At Risk/Churning/Churned
5. Action mapping: value tier × churn segment → recommended intervention

### 3. Delivery Efficiency Intelligence
**Business question:** Which zones and partners are underperforming?

Metrics:
- P50, P90, P99 delivery times (not just average — skew matters)
- SLA breach % by zone, hour, and partner
- Demand × supply imbalance: unassigned orders per zone

### 4. Restaurant Health Scoring
Composite 0–100 score from:
- Food rating weight (20 pts)
- Cancellation rate weight (20 pts)
- Recent activity weight (20 pts)
- Platform rating weight (20 pts)
- Delivery speed weight (20 pts)

### 5. Financial Analytics
- GMV decomposition: gross → discounts → net → COGS proxy → contribution margin
- Take rate monitoring: platform_commission / GMV
- Promotion ROI: (commission - discount_cost) / discount_cost × 100

## SQL Patterns Used

| Pattern | Where Used | Why |
|---------|-----------|-----|
| `NTILE(5)` | RFM scoring | Quintile rank without hard thresholds |
| `LAG()` | MoM growth | Compare to prior period without self-join |
| `PERCENTILE_CONT(0.5)` | Delivery times | Median is more robust than mean for skewed data |
| `FILTER (WHERE ...)` | Conditional aggregation | Clean pivot replacement |
| Recursive CTE | Category hierarchy | Unlimited depth traversal |
| Correlated subquery | Partner vs zone avg | Row-level comparison to group |
| `FIRST_VALUE / LAST_VALUE` | First/last restaurant per customer | Window frame analysis |
