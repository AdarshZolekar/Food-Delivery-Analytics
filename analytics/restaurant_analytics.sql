-- =============================================================================
-- FILE:        analytics/restaurant_analytics.sql
-- Description: Restaurant performance, growth trends, cuisine analysis,
--              menu item insights, and partner health scoring.
-- =============================================================================

-- =============================================================================
-- Q1: Restaurant Revenue Ranking with Percentiles and Growth
-- =============================================================================

WITH monthly_revenue AS (
    SELECT
        r.restaurant_id,
        r.restaurant_name,
        r.cuisine_type,
        ci.city_name,
        DATE_TRUNC('month', o.order_timestamp)::date    AS month,
        COUNT(o.order_id)                               AS orders,
        ROUND(SUM(o.total_amount)::numeric, 2)          AS revenue,
        ROUND(SUM(o.platform_commission)::numeric, 2)   AS platform_revenue,
        COUNT(DISTINCT o.customer_id)                   AS unique_customers
    FROM orders o
    JOIN restaurants r  ON o.restaurant_id = r.restaurant_id
    JOIN cities     ci  ON r.city_id       = ci.city_id
    WHERE o.order_status = 'Delivered'
    GROUP BY 1, 2, 3, 4, 5
),
with_growth AS (
    SELECT *,
        LAG(revenue) OVER (PARTITION BY restaurant_id ORDER BY month)  AS prev_month_rev,
        ROUND(
            (revenue - LAG(revenue) OVER (PARTITION BY restaurant_id ORDER BY month))
            / NULLIF(LAG(revenue) OVER (PARTITION BY restaurant_id ORDER BY month), 0) * 100
        ::numeric, 1)                                                  AS mom_growth_pct
    FROM monthly_revenue
)
SELECT
    restaurant_id, restaurant_name, cuisine_type, city_name,
    month, orders, revenue, platform_revenue, unique_customers,
    prev_month_rev, mom_growth_pct,
    RANK()        OVER (PARTITION BY month ORDER BY revenue DESC)      AS month_rank,
    NTILE(4)      OVER (PARTITION BY month ORDER BY revenue)           AS revenue_quartile,
    ROUND(PERCENT_RANK() OVER (PARTITION BY month ORDER BY revenue) * 100 ::numeric, 1)
                                                                       AS revenue_percentile
FROM with_growth
ORDER BY month DESC, revenue DESC;


-- =============================================================================
-- Q2: Cuisine Type Performance — Market Share and Growth
-- =============================================================================

SELECT
    r.cuisine_type,
    COUNT(DISTINCT r.restaurant_id)                     AS restaurants,
    COUNT(o.order_id)                                   AS total_orders,
    ROUND(SUM(o.total_amount)::numeric, 2)              AS total_revenue,
    ROUND(AVG(o.total_amount)::numeric, 2)              AS avg_order_value,
    ROUND(AVG(r.rating)::numeric, 2)                    AS avg_restaurant_rating,
    ROUND(SUM(o.total_amount) * 100.0 / SUM(SUM(o.total_amount)) OVER ()
    ::numeric, 2)                                       AS revenue_share_pct,
    RANK() OVER (ORDER BY SUM(o.total_amount) DESC)     AS revenue_rank
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
GROUP BY r.cuisine_type
ORDER BY total_revenue DESC;


-- =============================================================================
-- Q3: Restaurant Health Score — Composite KPI
-- =============================================================================

WITH rest_metrics AS (
    SELECT
        r.restaurant_id,
        r.restaurant_name,
        r.cuisine_type,
        ci.city_name,
        r.rating                                            AS platform_rating,
        COUNT(o.order_id)                                   AS total_orders,
        COUNT(o.order_id) FILTER (WHERE o.order_status = 'Cancelled')
                                                            AS cancelled_orders,
        ROUND(AVG(o.total_amount)::numeric, 2)              AS avg_order_value,
        ROUND(AVG(rv.food_rating)::numeric, 2)              AS avg_food_rating,
        ROUND(AVG(d.actual_time_mins)::numeric, 1)          AS avg_prep_to_delivery,
        COUNT(st.ticket_id)                                 AS support_tickets,
        COUNT(o.order_id) FILTER (WHERE o.order_date >= CURRENT_DATE - 30)
                                                            AS orders_last_30d
    FROM restaurants r
    JOIN cities ci ON r.city_id = ci.city_id
    LEFT JOIN orders o ON r.restaurant_id = o.restaurant_id
    LEFT JOIN reviews rv ON r.restaurant_id = rv.restaurant_id
    LEFT JOIN deliveries d ON o.order_id = d.order_id
    LEFT JOIN support_tickets st ON o.order_id = st.order_id
    WHERE r.is_active = TRUE
    GROUP BY r.restaurant_id, r.restaurant_name, r.cuisine_type,
             ci.city_name, r.rating
)
SELECT
    restaurant_id, restaurant_name, cuisine_type, city_name,
    total_orders, orders_last_30d,
    avg_food_rating, platform_rating,
    ROUND(cancelled_orders * 100.0 / NULLIF(total_orders, 0) ::numeric, 2)
                                                    AS cancellation_rate_pct,
    avg_prep_to_delivery,
    support_tickets,
    -- Health score: 0-100 composite
    ROUND(
        COALESCE(avg_food_rating, 0)      * 20 +    -- 0-20: food quality
        GREATEST(0, 10 - cancelled_orders * 100.0 / NULLIF(total_orders,0)) * 2 +  -- 0-20: low cancellations
        LEAST(20, orders_last_30d / 5.0) +           -- 0-20: recent activity
        COALESCE(platform_rating, 0) * 4 +           -- 0-20: platform rating
        GREATEST(0, 20 - COALESCE(avg_prep_to_delivery, 40)) -- 0-20: fast delivery
    ::numeric, 1)                                   AS health_score,
    CASE
        WHEN avg_food_rating >= 4.5 AND cancelled_orders * 100.0 / NULLIF(total_orders,0) < 3
        THEN '⭐ Star Partner'
        WHEN avg_food_rating >= 4.0 THEN '✅ Good Partner'
        WHEN avg_food_rating < 3.5  THEN '⚠️  Needs Improvement'
        ELSE '📊 Average'
    END                                             AS partner_status
FROM rest_metrics
ORDER BY health_score DESC NULLS LAST;


-- =============================================================================
-- Q4: Top Menu Items by Revenue and Frequency
-- =============================================================================

SELECT
    mi.item_id,
    mi.item_name,
    r.restaurant_name,
    r.cuisine_type,
    mi.price,
    mi.is_vegetarian,
    mi.is_bestseller,
    COUNT(oi.order_item_id)                         AS times_ordered,
    ROUND(SUM(oi.item_total)::numeric, 2)           AS total_revenue,
    RANK() OVER (ORDER BY COUNT(oi.order_item_id) DESC)         AS order_freq_rank,
    RANK() OVER (ORDER BY SUM(oi.item_total) DESC)              AS revenue_rank,
    RANK() OVER (PARTITION BY r.cuisine_type
                 ORDER BY COUNT(oi.order_item_id) DESC)         AS cuisine_rank,
    -- Was it popular before it was marked bestseller?
    mi.is_bestseller                                AS officially_bestseller
FROM order_items oi
JOIN menu_items  mi ON oi.item_id       = mi.item_id
JOIN restaurants r  ON mi.restaurant_id = r.restaurant_id
JOIN orders      o  ON oi.order_id      = o.order_id
WHERE o.order_status = 'Delivered'
GROUP BY mi.item_id, mi.item_name, r.restaurant_name, r.cuisine_type,
         mi.price, mi.is_vegetarian, mi.is_bestseller
ORDER BY times_ordered DESC
LIMIT 50;


-- =============================================================================
-- Q5: New Restaurant Onboarding Ramp — Time to First 100 Orders
-- =============================================================================

WITH order_milestones AS (
    SELECT
        r.restaurant_id,
        r.restaurant_name,
        r.cuisine_type,
        ci.city_name,
        r.joining_date,
        COUNT(o.order_id)                                       AS total_orders,
        MIN(o.order_timestamp)::date                            AS first_order_date,
        -- Date when each milestone was reached
        MIN(o.order_timestamp) FILTER (
            WHERE o.order_id IN (
                SELECT order_id FROM (
                    SELECT order_id,
                           ROW_NUMBER() OVER (PARTITION BY restaurant_id
                                              ORDER BY order_timestamp) AS rn
                    FROM orders WHERE order_status = 'Delivered'
                ) t WHERE rn = 100
            )
        )::date                                                 AS date_100th_order,
        MIN(o.order_timestamp) FILTER (
            WHERE o.order_id IN (
                SELECT order_id FROM (
                    SELECT order_id,
                           ROW_NUMBER() OVER (PARTITION BY restaurant_id
                                              ORDER BY order_timestamp) AS rn
                    FROM orders WHERE order_status = 'Delivered'
                ) t WHERE rn = 500
            )
        )::date                                                 AS date_500th_order
    FROM restaurants r
    JOIN cities ci ON r.city_id = ci.city_id
    LEFT JOIN orders o ON r.restaurant_id = o.restaurant_id
    GROUP BY r.restaurant_id, r.restaurant_name, r.cuisine_type, ci.city_name, r.joining_date
)
SELECT
    restaurant_name, cuisine_type, city_name, joining_date,
    total_orders, first_order_date,
    date_100th_order,
    date_100th_order - joining_date                             AS days_to_100_orders,
    date_500th_order - joining_date                             AS days_to_500_orders,
    CASE
        WHEN date_100th_order - joining_date <= 30  THEN 'Fast Ramp'
        WHEN date_100th_order - joining_date <= 60  THEN 'Normal Ramp'
        WHEN date_100th_order - joining_date <= 90  THEN 'Slow Ramp'
        ELSE 'Struggling'
    END                                                         AS ramp_category
FROM order_milestones
WHERE total_orders >= 100
ORDER BY days_to_100_orders NULLS LAST;
