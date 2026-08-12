# KPI Dictionary — SwiftEats Analytics

## Revenue KPIs

| KPI | Formula | Grain | Owner |
|-----|---------|-------|-------|
| **GMV** | `SUM(total_amount)` on all non-cancelled orders | Any | Finance |
| **Net Revenue** | GMV minus refunds | Any | Finance |
| **Platform Revenue** | `SUM(platform_commission)` on delivered orders | Any | Finance |
| **Take Rate %** | `platform_revenue / GMV × 100` | Any | Finance |
| **AOV** | `net_revenue / COUNT(delivered orders)` | Any | Product |
| **Discount Rate %** | `total_discounts / GMV × 100` | Any | Marketing |
| **Refund Rate %** | `total_refunds / net_revenue × 100` | Any | Ops |

## Customer KPIs

| KPI | Formula | Target | Owner |
|-----|---------|--------|-------|
| **MAU** | `COUNT(DISTINCT customer_id)` with ≥1 order in 30 days | Growth | Product |
| **Retention Rate M1** | Cohort customers who order again in month 2 / cohort size | >30% | Product |
| **Churn Rate** | 1 − Retention Rate | <70% | Product |
| **Customer LTV** | `SUM(total_amount)` per customer lifetime | — | Finance |
| **Repeat Purchase Rate** | Customers with ≥2 orders / total ordering customers | >60% | Marketing |
| **CAC Proxy** | marketing_spend / new_customers | Minimize | Marketing |
| **LTV:CAC** | avg_ltv / cac | >3× | Finance |

## Delivery Operations KPIs

| KPI | Formula | Target | Owner |
|-----|---------|--------|-------|
| **Avg Delivery Time** | `AVG(actual_time_mins)` on delivered orders | ≤30 min | Ops |
| **Median Delivery Time** | `PERCENTILE_CONT(0.5)` of actual_time_mins | ≤28 min | Ops |
| **SLA Breach Rate %** | `COUNT(sla_breached=TRUE) / total_deliveries × 100` | <10% | Ops |
| **On-Time Rate %** | `COUNT(on_time=TRUE) / delivered × 100` | >85% | Ops |
| **Partner Utilisation** | avg deliveries per active partner per day | 6–8/day | Ops |
| **Cancellation Rate %** | `COUNT(Cancelled) / total_orders × 100` | <5% | Ops |

## Restaurant Partner KPIs

| KPI | Formula | Target | Owner |
|-----|---------|--------|-------|
| **Avg Food Rating** | `AVG(food_rating)` from reviews | ≥4.0 | Partner Success |
| **Restaurant Activation Rate** | Restaurants with ≥1 order in 30d / total | >80% | BD |
| **Avg Order Value per Restaurant** | GMV / order count | Grow | Finance |
| **Time to 100 Orders** | Days from joining_date to 100th delivered order | <30d | BD |

## RFM Segment Definitions

| Segment | Recency | Frequency | Monetary | Action |
|---------|---------|-----------|----------|--------|
| Champions | R≥4, F≥4, M≥4 | High | High | Reward, early access |
| Loyal | R≥3, F≥3 | Medium-High | Medium-High | Upsell |
| Promising | R≥4, F≤2 | Low | Low | Convert to habit |
| New Customer | R=5, F=1 | Very Low | Any | Onboarding flow |
| At Risk | R≤2, F≥4 | Was high | Was high | Win-back offer |
| Hibernating | R≤3, F≤2 | Low | Low | Re-engagement push |
| Lost | R=1, F=1 | Very Low | Very Low | Low-cost reactivation |

## SLA Definitions

| Metric | SLA Target | Breach Threshold |
|--------|-----------|------------------|
| Delivery time | ≤45 minutes | >45 minutes (`sla_breached = TRUE`) |
| Support ticket (Critical) | Resolved <2 hours | >2 hours |
| Support ticket (High) | Resolved <8 hours | >8 hours |
| Support ticket (Medium) | Resolved <24 hours | >24 hours |
| Partner assignment | <3 minutes from order placement | >5 minutes |
