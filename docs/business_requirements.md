# Business Requirements

## Company Profile

**SwiftEats** operates food delivery across 10 Indian cities with 5,000+ restaurant partners and 10,000 delivery partners. The analytics team supports three strategic goals:

1. Grow GMV 25% YoY while improving contribution margin
2. Reduce customer churn (Month-1 retention target: >35%)
3. Achieve delivery SLA compliance >90% across all zones

---

## Stakeholder Map

| Stakeholder | Primary Questions | Dashboard |
|---|---|---|
| CEO / CFO | GMV growth, take rate, profitability | Executive Overview |
| VP Operations | SLA compliance, partner supply, zone risk | Delivery Intelligence |
| CMO | Customer retention, churn, acquisition ROI | Customer Intelligence |
| Partner Success | Restaurant health, ramp rate | Restaurant Partner |
| City Managers | Zone-level demand, partner utilisation | Operational |

---

## Functional Requirements

### FR-01: Revenue Reporting
- Daily, weekly, monthly, and YTD GMV
- Platform revenue (commission) separately from GMV
- Breakdown by city, cuisine, restaurant, and payment method

### FR-02: Customer Retention Analytics
- Monthly cohort retention matrix (M0–M12)
- RFM segmentation updated weekly
- Churn risk identification with value-tier overlay
- LTV calculation: historical and projected 12-month

### FR-03: Delivery Operations
- Average and median delivery time by zone, hour, partner
- SLA breach rate with zone-level risk flagging
- Partner utilisation (deliveries/day) and earnings
- Cancellation root cause breakdown

### FR-04: Restaurant Partner Analytics
- Revenue and order ranking with city and cuisine breakdown
- Health score: composite of rating, cancellations, activity, speed
- Onboarding ramp: time to 100/500 orders
- Menu item performance: top sellers, ABC classification

### FR-05: Peak Demand Intelligence
- Hour × day demand heatmap with demand_index
- Staffing recommendations per zone and time window
- Festival and weekend demand spike detection

---

## Non-Functional Requirements

| Requirement | Target |
|---|---|
| Dashboard load time (materialized views) | < 200 ms |
| Ad-hoc analytics (30-day window) | < 2 s |
| Full ETL load (1M orders) | < 15 minutes |
| Materialized view refresh | < 5 minutes |
| Data freshness for dashboards | Nightly by 04:00 IST |

---

## Data Quality Thresholds

| Check | Maximum Failure Rate |
|---|---|
| Null on required FK columns | 0% |
| Delivery time ≤ 0 | 0% |
| Rating outside 1–5 | 0% |
| Total amount < 0 | 0% |
| Cancellation without reason | <0.5% |
