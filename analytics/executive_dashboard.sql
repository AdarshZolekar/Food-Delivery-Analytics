-- =============================================================================
-- FILE:        analytics/executive_dashboard.sql
-- Description: C-suite KPIs — platform health, growth, unit economics.
-- =============================================================================

-- =============================================================================
-- Q1: Platform Health — Current Month KPI Tiles
-- =============================================================================

WITH current_month AS (
    SELECT
        SUM(total_amount) FILTER (WHERE order_status != 'Cancelled') AS gmv,
        SUM(platform_commission) FILTER (WHERE order_status = 'Delivered') AS platform_rev,
        COUNT(*) AS total_orders,
        COUNT(*) FILTER (WHERE order_status = 'Delivered') AS delivered,
        COUNT(*) FILTER (WHERE order_status = 'Cancelled') AS cancelled,
        COUNT(DISTINCT customer_id) AS active_customers,
        COUNT(DISTINCT restaurant_id) AS active_restaurants,
        SUM(discount_amount) AS discounts
    FROM orders
    WHERE order_date >= DATE_TRUNC('month', CURRENT_DATE)
),
prior_month AS (
    SELECT
        SUM(total_amount) FILTER (WHERE order_status != 'Cancelled') AS gmv,
        COUNT(*) FILTER (WHERE order_status = 'Delivered') AS delivered,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM orders
    WHERE order_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
      AND order_date <  DATE_TRUNC('month', CURRENT_DATE)
)
SELECT
    TO_CHAR(CURRENT_DATE, 'Month YYYY')                         AS period,
    ROUND(cm.gmv::numeric, 2)                                   AS mtd_gmv,
    ROUND(cm.platform_rev::numeric, 2)                          AS platform_revenue,
    ROUND(cm.platform_rev / NULLIF(cm.gmv, 0) * 100::numeric, 2)
                                                                AS take_rate_pct,
    cm.total_orders,
    cm.delivered                                                AS delivered_orders,
    cm.cancelled                                                AS cancelled_orders,
    ROUND(cm.cancelled * 100.0 / NULLIF(cm.total_orders, 0)::numeric, 2)
                                                                AS cancellation_rate_pct,
    cm.active_customers,
    cm.active_restaurants,
    ROUND(cm.gmv / NULLIF(cm.delivered, 0)::numeric, 2)         AS avg_order_value,
    ROUND(cm.discounts::numeric, 2)                             AS discounts_given,
    ROUND(cm.discounts / NULLIF(cm.gmv, 0) * 100::numeric, 2)  AS discount_rate_pct,
    -- MoM growth
    ROUND((cm.gmv - pm.gmv) / NULLIF(pm.gmv, 0) * 100::numeric, 1)
                                                                AS gmv_mom_growth_pct,
    ROUND((cm.active_customers - pm.active_customers)
        / NULLIF(pm.active_customers, 0) * 100::numeric, 1)    AS customer_mom_growth_pct
FROM current_month cm, prior_month pm;


-- =============================================================================
-- Q2: 12-Month Rolling GMV Trend
-- =============================================================================

SELECT
    mk.day                                              AS month,
    mk.gross_revenue                                    AS gmv,
    mk.platform_revenue,
    mk.avg_order_value,
    mk.total_orders,
    mk.active_customers,
    mk.cancellation_rate_pct,
    -- Running total
    SUM(mk.gross_revenue) OVER (
        ORDER BY mk.day ROWS UNBOUNDED PRECEDING
    )                                                   AS cumulative_gmv,
    -- 3-month moving average
    ROUND(AVG(mk.gross_revenue) OVER (
        ORDER BY mk.day ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )::numeric, 2)                                      AS ma_3month_gmv,
    -- YoY comparison
    LAG(mk.gross_revenue, 12) OVER (ORDER BY mk.day)    AS same_month_last_year,
    ROUND(
        (mk.gross_revenue - LAG(mk.gross_revenue, 12) OVER (ORDER BY mk.day))
        / NULLIF(LAG(mk.gross_revenue, 12) OVER (ORDER BY mk.day), 0) * 100
    ::numeric, 1)                                       AS yoy_growth_pct
FROM mv_daily_kpi mk
WHERE mk.day >= CURRENT_DATE - INTERVAL '24 months'
  AND EXTRACT(DAY FROM mk.day) = 1   -- First of each month only
ORDER BY month DESC;


-- =============================================================================
-- Q3: Unit Economics Dashboard
-- =============================================================================

WITH period_data AS (
    SELECT
        ROUND(SUM(total_amount) FILTER (WHERE order_status = 'Delivered')::numeric,2)    AS net_gmv,
        ROUND(SUM(platform_commission) FILTER (WHERE order_status = 'Delivered')::numeric,2) AS platform_rev,
        ROUND(SUM(discount_amount)::numeric, 2)                 AS total_discounts,
        COUNT(*) FILTER (WHERE order_status = 'Delivered')      AS delivered_orders,
        COUNT(DISTINCT customer_id)                             AS unique_customers,
        COUNT(DISTINCT restaurant_id)                           AS unique_restaurants
    FROM orders
    WHERE order_date >= CURRENT_DATE - INTERVAL '30 days'
),
delivery_costs AS (
    SELECT ROUND(SUM(partner_earnings)::numeric, 2) AS total_payout
    FROM deliveries
    WHERE delivered_at >= CURRENT_DATE - INTERVAL '30 days'
      AND delivery_status = 'Delivered'
)
SELECT
    pd.net_gmv,
    pd.platform_rev,
    dc.total_payout                                     AS delivery_cost,
    pd.total_discounts,
    ROUND(pd.platform_rev - dc.total_payout - pd.total_discounts ::numeric, 2)
                                                        AS contribution_margin,
    ROUND(pd.net_gmv / NULLIF(pd.delivered_orders, 0) ::numeric, 2)
                                                        AS avg_order_value,
    ROUND(pd.platform_rev / NULLIF(pd.delivered_orders, 0) ::numeric, 2)
                                                        AS revenue_per_order,
    ROUND(dc.total_payout / NULLIF(pd.delivered_orders, 0) ::numeric, 2)
                                                        AS delivery_cost_per_order,
    ROUND(pd.total_discounts / NULLIF(pd.delivered_orders, 0) ::numeric, 2)
                                                        AS discount_per_order,
    ROUND((pd.platform_rev - dc.total_payout - pd.total_discounts)
        / NULLIF(pd.delivered_orders, 0) ::numeric, 2) AS cm_per_order,
    -- Blended take rate
    ROUND(pd.platform_rev / NULLIF(pd.net_gmv, 0) * 100::numeric, 2)
                                                        AS take_rate_pct,
    pd.unique_customers,
    pd.unique_restaurants
FROM period_data pd, delivery_costs dc;


-- =============================================================================
-- Q4: Customer Growth KPIs — New vs Returning Split
-- =============================================================================

WITH first_orders AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_timestamp))::date AS first_order_month
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
monthly_orders AS (
    SELECT
        DATE_TRUNC('month', o.order_timestamp)::date        AS month,
        COUNT(DISTINCT o.customer_id)                       AS total_active,
        COUNT(DISTINCT o.customer_id) FILTER (
            WHERE DATE_TRUNC('month', fo.first_order_month) =
                  DATE_TRUNC('month', o.order_timestamp)
        )                                                   AS new_customers,
        COUNT(DISTINCT o.customer_id) FILTER (
            WHERE DATE_TRUNC('month', fo.first_order_month) <
                  DATE_TRUNC('month', o.order_timestamp)
        )                                                   AS returning_customers
    FROM orders o
    JOIN first_orders fo USING (customer_id)
    WHERE o.order_status = 'Delivered'
    GROUP BY DATE_TRUNC('month', o.order_timestamp)
)
SELECT
    month,
    total_active,
    new_customers,
    returning_customers,
    ROUND(new_customers * 100.0 / NULLIF(total_active, 0)::numeric, 1)
                                                AS new_pct,
    ROUND(returning_customers * 100.0 / NULLIF(total_active, 0)::numeric, 1)
                                                AS returning_pct,
    LAG(new_customers) OVER (ORDER BY month)   AS prev_new_customers,
    ROUND(
        (new_customers - LAG(new_customers) OVER (ORDER BY month))
        / NULLIF(LAG(new_customers) OVER (ORDER BY month), 0) * 100
    ::numeric, 1)                              AS new_customer_growth_pct
FROM monthly_orders
ORDER BY month DESC
LIMIT 24;
