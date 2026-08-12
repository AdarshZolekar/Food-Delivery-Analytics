-- =============================================================================
-- FILE:        analytics/operational_analytics.sql
-- Description: Platform operations — support tickets, refunds, promotions,
--              peak demand forecasting, and order failure analysis.
-- =============================================================================

-- =============================================================================
-- Q1: Peak Order Time Analysis — Full Heatmap with Business Recommendations
-- =============================================================================

WITH hourly_stats AS (
    SELECT
        EXTRACT(DOW FROM order_timestamp)::INT      AS day_of_week,
        TO_CHAR(order_timestamp, 'Day')             AS day_name,
        EXTRACT(HOUR FROM order_timestamp)::INT     AS hour,
        COUNT(*)                                    AS orders,
        ROUND(AVG(total_amount)::numeric, 2)        AS avg_order_value,
        COUNT(*) FILTER (WHERE order_status = 'Delivered') AS delivered,
        COUNT(*) FILTER (WHERE order_status = 'Cancelled') AS cancelled
    FROM orders
    GROUP BY 1, 2, 3
),
with_baseline AS (
    SELECT *,
        AVG(orders) OVER ()                         AS global_avg,
        AVG(orders) OVER (PARTITION BY day_of_week) AS day_avg,
        -- Moving average over adjacent 3 hours
        ROUND(AVG(orders) OVER (
            PARTITION BY day_of_week
            ORDER BY hour
            ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
        )::numeric, 1)                              AS smoothed_orders
    FROM hourly_stats
)
SELECT
    day_name,
    day_of_week,
    hour,
    LPAD(hour::TEXT, 2, '0') || ':00'               AS hour_label,
    orders,
    ROUND(smoothed_orders, 0)                       AS smoothed_orders,
    avg_order_value,
    ROUND(orders * 100.0 / NULLIF(global_avg, 0) ::numeric, 1)
                                                    AS demand_index,
    -- Rush classification
    CASE
        WHEN hour BETWEEN 12 AND 14 THEN 'Lunch Rush 🍱'
        WHEN hour BETWEEN 19 AND 22 THEN 'Dinner Rush 🍽️'
        WHEN hour BETWEEN 23 AND 1  THEN 'Late Night 🌙'
        WHEN hour BETWEEN 7  AND 9  THEN 'Breakfast 🌅'
        ELSE 'Off-Peak'
    END                                             AS time_period,
    -- Recommended staff level
    CASE
        WHEN orders > global_avg * 1.8 THEN 'Max staffing needed'
        WHEN orders > global_avg * 1.3 THEN 'Increased staffing'
        WHEN orders > global_avg * 0.8 THEN 'Normal staffing'
        ELSE 'Reduced staffing OK'
    END                                             AS staffing_recommendation
FROM with_baseline
ORDER BY day_of_week, hour;


-- =============================================================================
-- Q2: Support Ticket Analysis — SLA and Resolution Performance
-- =============================================================================

SELECT
    issue_type,
    priority,
    COUNT(*)                                            AS total_tickets,
    COUNT(*) FILTER (WHERE status = 'Resolved')         AS resolved,
    COUNT(*) FILTER (WHERE status IN ('Open','In Progress')) AS open_tickets,
    COUNT(*) FILTER (WHERE sla_breached)                AS sla_breaches,
    ROUND(COUNT(*) FILTER (WHERE sla_breached) * 100.0
        / NULLIF(COUNT(*), 0)::numeric, 1)              AS sla_breach_pct,
    ROUND(AVG(
        CASE WHEN resolved_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (resolved_at - created_at)) / 3600
             ELSE NULL END
    )::numeric, 1)                                      AS avg_resolution_hrs,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (resolved_at - created_at)) / 3600
    )::numeric, 1)                                      AS p90_resolution_hrs
FROM support_tickets
GROUP BY issue_type, priority
ORDER BY
    CASE priority WHEN 'Critical' THEN 1 WHEN 'High' THEN 2
                  WHEN 'Medium' THEN 3 ELSE 4 END,
    total_tickets DESC;


-- =============================================================================
-- Q3: Promotion Effectiveness Analysis
-- =============================================================================

WITH promo_orders AS (
    SELECT
        p.promo_code,
        p.promo_name,
        p.promo_type,
        p.discount_value,
        COUNT(o.order_id)                           AS promo_orders,
        ROUND(AVG(o.total_amount)::numeric, 2)      AS avg_order_value,
        ROUND(AVG(o.discount_amount)::numeric, 2)   AS avg_discount,
        ROUND(SUM(o.total_amount)::numeric, 2)      AS total_gmv,
        ROUND(SUM(o.discount_amount)::numeric, 2)   AS total_discount_cost,
        ROUND(SUM(o.platform_commission)::numeric, 2) AS total_commission
    FROM promotions p
    JOIN orders o ON p.promotion_id = o.promotion_id
    WHERE o.order_status = 'Delivered'
    GROUP BY p.promo_code, p.promo_name, p.promo_type, p.discount_value
),
baseline AS (
    SELECT ROUND(AVG(total_amount)::numeric, 2) AS baseline_aov
    FROM orders WHERE order_status = 'Delivered' AND promotion_id IS NULL
)
SELECT
    po.promo_code,
    po.promo_name,
    po.promo_type,
    po.discount_value,
    po.promo_orders,
    po.avg_order_value,
    b.baseline_aov,
    ROUND(po.avg_order_value - b.baseline_aov ::numeric, 2)  AS aov_lift,
    po.avg_discount,
    po.total_gmv,
    po.total_discount_cost,
    po.total_commission,
    ROUND(po.total_commission - po.total_discount_cost ::numeric, 2)
                                                    AS net_platform_gain,
    -- ROI: is the promo profitable for the platform?
    ROUND((po.total_commission - po.total_discount_cost) * 100.0
        / NULLIF(po.total_discount_cost, 0)::numeric, 1)
                                                    AS promotion_roi_pct
FROM promo_orders po
CROSS JOIN baseline b
ORDER BY net_platform_gain DESC;


-- =============================================================================
-- Q4: Order Funnel Analysis — Drop-offs by Stage
-- =============================================================================

WITH funnel AS (
    SELECT
        COUNT(*)                                            AS total_placed,
        COUNT(*) FILTER (WHERE order_status != 'Cancelled') AS past_placement,
        COUNT(*) FILTER (WHERE confirmed_at IS NOT NULL)    AS confirmed,
        COUNT(*) FILTER (WHERE prepared_at IS NOT NULL)     AS prepared,
        COUNT(*) FILTER (WHERE picked_up_at IS NOT NULL)    AS picked_up,
        COUNT(*) FILTER (WHERE order_status = 'Delivered')  AS delivered
    FROM orders
)
SELECT
    'Placed'        AS stage, total_placed          AS orders, 100.0 AS conversion_pct FROM funnel
UNION ALL
SELECT 'Not Cancelled', past_placement, ROUND(past_placement*100.0/NULLIF(total_placed,0),1) FROM funnel
UNION ALL
SELECT 'Confirmed', confirmed, ROUND(confirmed*100.0/NULLIF(total_placed,0),1) FROM funnel
UNION ALL
SELECT 'Prepared', prepared, ROUND(prepared*100.0/NULLIF(total_placed,0),1) FROM funnel
UNION ALL
SELECT 'Picked Up', picked_up, ROUND(picked_up*100.0/NULLIF(total_placed,0),1) FROM funnel
UNION ALL
SELECT 'Delivered', delivered, ROUND(delivered*100.0/NULLIF(total_placed,0),1) FROM funnel
ORDER BY orders DESC;


-- =============================================================================
-- Q5: Revenue by City with MoM Trend
-- =============================================================================

WITH city_monthly AS (
    SELECT
        ci.city_id,
        ci.city_name,
        DATE_TRUNC('month', o.order_timestamp)::date    AS month,
        COUNT(o.order_id)                               AS orders,
        ROUND(SUM(o.total_amount)::numeric, 2)          AS revenue,
        COUNT(DISTINCT o.customer_id)                   AS active_customers,
        ROUND(AVG(o.total_amount)::numeric, 2)          AS aov
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN cities ci ON c.city_id = ci.city_id
    WHERE o.order_status = 'Delivered'
    GROUP BY ci.city_id, ci.city_name, DATE_TRUNC('month', o.order_timestamp)
)
SELECT
    city_name, month, orders, revenue, active_customers, aov,
    LAG(revenue) OVER (PARTITION BY city_id ORDER BY month) AS prev_month,
    ROUND(
        (revenue - LAG(revenue) OVER (PARTITION BY city_id ORDER BY month))
        / NULLIF(LAG(revenue) OVER (PARTITION BY city_id ORDER BY month), 0) * 100
    ::numeric, 1)                                           AS mom_growth_pct,
    ROUND(SUM(revenue) OVER (PARTITION BY city_id ORDER BY month
        ROWS UNBOUNDED PRECEDING)::numeric, 2)              AS cumulative_revenue,
    -- Moving average
    ROUND(AVG(revenue) OVER (PARTITION BY city_id ORDER BY month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)::numeric, 2)
                                                            AS ma_3month
FROM city_monthly
ORDER BY city_name, month DESC;


-- =============================================================================
-- Q6: Refund and Revenue Leakage Analysis
-- =============================================================================

SELECT
    DATE_TRUNC('month', o.order_timestamp)::date        AS month,
    COUNT(*) FILTER (WHERE o.is_refunded)               AS refunded_orders,
    ROUND(SUM(o.refund_amount) FILTER (WHERE o.is_refunded)::numeric, 2)
                                                        AS total_refunds,
    ROUND(SUM(o.total_amount)::numeric, 2)              AS gross_revenue,
    ROUND(
        SUM(o.refund_amount) FILTER (WHERE o.is_refunded)
        / NULLIF(SUM(o.total_amount), 0) * 100 ::numeric, 2
    )                                                   AS refund_rate_pct,
    COUNT(*) FILTER (WHERE o.order_status = 'Cancelled') AS cancellations,
    ROUND(
        COUNT(*) FILTER (WHERE o.order_status = 'Cancelled')
        * 100.0 / NULLIF(COUNT(*), 0)::numeric, 2
    )                                                   AS cancellation_rate_pct,
    ROUND(SUM(o.discount_amount)::numeric, 2)           AS discount_cost,
    ROUND(
        SUM(o.discount_amount) / NULLIF(SUM(o.total_amount), 0) * 100 ::numeric, 2
    )                                                   AS discount_rate_pct
FROM orders o
GROUP BY DATE_TRUNC('month', o.order_timestamp)
ORDER BY month DESC;
