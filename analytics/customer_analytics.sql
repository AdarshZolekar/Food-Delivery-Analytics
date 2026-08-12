-- =============================================================================
-- FILE:        analytics/customer_analytics.sql
-- Description: Customer retention, RFM segmentation, cohort analysis,
--              churn prediction, LTV, and acquisition channel ROI.
-- =============================================================================

-- =============================================================================
-- Q1: Monthly Cohort Retention Matrix (M0 through M12)
-- =============================================================================

WITH first_order AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort_month
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
monthly_activity AS (
    SELECT
        fo.customer_id,
        fo.cohort_month,
        DATE_TRUNC('month', o.order_timestamp)::date        AS active_month,
        (
            EXTRACT(YEAR FROM AGE(
                DATE_TRUNC('month', o.order_timestamp),
                fo.cohort_month::TIMESTAMP)) * 12 +
            EXTRACT(MONTH FROM AGE(
                DATE_TRUNC('month', o.order_timestamp),
                fo.cohort_month::TIMESTAMP))
        )::INT                                              AS months_since_join
    FROM first_order fo
    JOIN orders o USING (customer_id)
    WHERE o.order_status = 'Delivered'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM first_order GROUP BY 1
)
SELECT
    TO_CHAR(ma.cohort_month, 'YYYY-MM')             AS cohort,
    cs.cohort_size,
    ma.months_since_join                            AS month_number,
    COUNT(DISTINCT ma.customer_id)                  AS active_customers,
    ROUND(
        COUNT(DISTINCT ma.customer_id) * 100.0 / cs.cohort_size
    ::numeric, 1)                                   AS retention_pct,
    -- Churn vs previous month
    ROUND(
        100.0 - COUNT(DISTINCT ma.customer_id) * 100.0 / cs.cohort_size
    ::numeric, 1)                                   AS cumulative_churn_pct
FROM monthly_activity ma
JOIN cohort_sizes cs USING (cohort_month)
WHERE ma.months_since_join BETWEEN 0 AND 12
GROUP BY ma.cohort_month, cs.cohort_size, ma.months_since_join
ORDER BY ma.cohort_month, ma.months_since_join;


-- =============================================================================
-- Q2: RFM Segmentation (from materialized view + enrichment)
-- =============================================================================

SELECT
    rfm_segment,
    COUNT(*)                                            AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () ::numeric, 2)
                                                        AS pct_of_customers,
    ROUND(AVG(monetary)::numeric, 2)                    AS avg_lifetime_spend,
    ROUND(SUM(monetary)::numeric, 2)                    AS total_revenue,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER () ::numeric, 2)
                                                        AS pct_of_revenue,
    ROUND(AVG(recency_days)::numeric, 0)                AS avg_days_since_order,
    ROUND(AVG(frequency::numeric), 1)                   AS avg_orders,
    ROUND(AVG(r_score)::numeric, 2)                     AS avg_r_score,
    ROUND(AVG(f_score)::numeric, 2)                     AS avg_f_score,
    ROUND(AVG(m_score)::numeric, 2)                     AS avg_m_score
FROM mv_customer_rfm
GROUP BY rfm_segment
ORDER BY avg_lifetime_spend DESC;


-- =============================================================================
-- Q3: Customer Lifetime Value (Historical + Projected)
-- =============================================================================

WITH customer_metrics AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.customer_tier,
        ci.city_name,
        c.acquisition_channel,
        c.registration_date,
        COUNT(DISTINCT o.order_id)                      AS total_orders,
        ROUND(SUM(o.total_amount)::numeric, 2)          AS historical_ltv,
        ROUND(AVG(o.total_amount)::numeric, 2)          AS avg_order_value,
        MIN(o.order_timestamp)::date                    AS first_order_date,
        MAX(o.order_timestamp)::date                    AS last_order_date,
        (CURRENT_DATE - MIN(o.order_timestamp)::date)   AS customer_age_days,
        -- Orders per month
        ROUND(
            COUNT(DISTINCT o.order_id)::numeric /
            NULLIF((CURRENT_DATE - MIN(o.order_timestamp)::date) / 30.0, 0)
        , 2)                                            AS orders_per_month
    FROM customers c
    JOIN cities ci ON c.city_id = ci.city_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
    GROUP BY c.customer_id, c.customer_name, c.customer_tier,
             ci.city_name, c.acquisition_channel, c.registration_date
)
SELECT
    customer_id, customer_name, customer_tier, city_name,
    acquisition_channel, total_orders,
    historical_ltv, avg_order_value,
    first_order_date, last_order_date, customer_age_days,
    orders_per_month,
    -- Projected 12-month LTV = orders_per_month × 12 × avg_order_value
    ROUND(orders_per_month * 12 * avg_order_value ::numeric, 2)
                                                        AS projected_12m_ltv,
    RANK() OVER (ORDER BY historical_ltv DESC)          AS ltv_rank,
    NTILE(10) OVER (ORDER BY historical_ltv)            AS ltv_decile,
    ROUND(PERCENT_RANK() OVER (ORDER BY historical_ltv) * 100 ::numeric, 1)
                                                        AS ltv_percentile
FROM customer_metrics
ORDER BY historical_ltv DESC;


-- =============================================================================
-- Q4: Churn Risk Scoring — Behavioral Signals
-- =============================================================================

WITH customer_behaviour AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.customer_tier,
        ci.city_name,
        CURRENT_DATE - MAX(o.order_date)                AS days_since_last_order,
        COUNT(DISTINCT o.order_id)                      AS total_orders,
        ROUND(SUM(o.total_amount)::numeric, 2)          AS total_spent,
        -- Trend: are they ordering less frequently?
        COUNT(o.order_id) FILTER (
            WHERE o.order_date >= CURRENT_DATE - 30)    AS orders_last_30d,
        COUNT(o.order_id) FILTER (
            WHERE o.order_date BETWEEN CURRENT_DATE - 60 AND CURRENT_DATE - 31)
                                                        AS orders_prev_30d,
        COUNT(st.ticket_id)                             AS support_tickets,
        COUNT(o.order_id) FILTER (
            WHERE o.order_status = 'Cancelled')         AS cancelled_orders
    FROM customers c
    JOIN cities ci ON c.city_id = ci.city_id
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN support_tickets st ON c.customer_id = st.customer_id
        AND st.created_at >= CURRENT_DATE - 90
    WHERE c.is_active = TRUE
    GROUP BY c.customer_id, c.customer_name, c.customer_tier, ci.city_name
)
SELECT
    customer_id, customer_name, customer_tier, city_name,
    days_since_last_order, total_orders, total_spent,
    orders_last_30d, orders_prev_30d, support_tickets,
    ROUND(cancelled_orders * 100.0 / NULLIF(total_orders, 0) ::numeric, 1)
                                                        AS cancellation_rate_pct,
    -- Trend signal
    CASE
        WHEN orders_last_30d < orders_prev_30d * 0.5    THEN 'Declining Fast'
        WHEN orders_last_30d < orders_prev_30d          THEN 'Declining'
        WHEN orders_last_30d = 0 AND orders_prev_30d > 0 THEN 'Stopped'
        ELSE 'Stable/Growing'
    END                                                 AS order_trend,
    -- Churn segment
    CASE
        WHEN days_since_last_order <= 14                THEN 'Active'
        WHEN days_since_last_order <= 30                THEN 'Cooling'
        WHEN days_since_last_order <= 60                THEN 'At Risk'
        WHEN days_since_last_order <= 90                THEN 'Churning'
        ELSE                                                 'Churned'
    END                                                 AS churn_segment,
    -- Priority action
    CASE
        WHEN days_since_last_order > 60 AND total_spent > 5000
        THEN '🚨 Win-Back VIP — send ₹100 voucher'
        WHEN days_since_last_order > 45 AND total_spent > 2000
        THEN '⚠️  Retention offer needed'
        WHEN orders_last_30d = 0 AND total_orders > 10
        THEN '📧 Re-engagement push notification'
        ELSE '— Standard flow'
    END                                                 AS recommended_action
FROM customer_behaviour
ORDER BY days_since_last_order DESC;


-- =============================================================================
-- Q5: Acquisition Channel ROI — CAC vs LTV
-- =============================================================================

WITH channel_metrics AS (
    SELECT
        c.acquisition_channel,
        COUNT(DISTINCT c.customer_id)                       AS total_customers,
        COUNT(DISTINCT c.customer_id) FILTER (
            WHERE o.order_id IS NOT NULL)                   AS ordering_customers,
        COUNT(DISTINCT o.order_id)                          AS total_orders,
        ROUND(SUM(o.total_amount)::numeric, 2)              AS total_revenue,
        ROUND(AVG(c_ltv.lifetime_value)::numeric, 2)        AS avg_ltv
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
        AND o.order_status = 'Delivered'
    LEFT JOIN (
        SELECT customer_id, SUM(total_amount) AS lifetime_value
        FROM orders WHERE order_status = 'Delivered'
        GROUP BY customer_id
    ) c_ltv ON c.customer_id = c_ltv.customer_id
    GROUP BY c.acquisition_channel
)
SELECT
    acquisition_channel,
    total_customers,
    ordering_customers,
    ROUND(ordering_customers * 100.0 / NULLIF(total_customers,0) ::numeric, 1)
                                                AS activation_rate_pct,
    total_orders,
    ROUND(total_orders::numeric / NULLIF(ordering_customers,0), 1)
                                                AS avg_orders_per_active,
    total_revenue,
    avg_ltv,
    ROUND(total_revenue / NULLIF(total_customers,0) ::numeric, 2)
                                                AS revenue_per_acquired_customer
FROM channel_metrics
ORDER BY avg_ltv DESC;


-- =============================================================================
-- Q6: Day-Since-Last-Order Distribution (Churn Curve)
-- =============================================================================

WITH last_orders AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN CURRENT_DATE - last_order_date <= 7   THEN '0-7 days'
        WHEN CURRENT_DATE - last_order_date <= 14  THEN '8-14 days'
        WHEN CURRENT_DATE - last_order_date <= 30  THEN '15-30 days'
        WHEN CURRENT_DATE - last_order_date <= 60  THEN '31-60 days'
        WHEN CURRENT_DATE - last_order_date <= 90  THEN '61-90 days'
        WHEN CURRENT_DATE - last_order_date <= 180 THEN '91-180 days'
        ELSE '180+ days (Churned)'
    END                                             AS recency_band,
    COUNT(*)                                        AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () ::numeric, 2)
                                                    AS pct_of_customers
FROM last_orders
GROUP BY 1
ORDER BY MIN(CURRENT_DATE - last_order_date);
