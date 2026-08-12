-- =============================================================================
-- FILE:        schema/views.sql
-- Description: Business views and materialized views for the analytics layer.
-- =============================================================================

-- =============================================================================
-- REGULAR VIEWS (live data)
-- =============================================================================

CREATE OR REPLACE VIEW v_order_detail AS
SELECT
    o.order_id,
    o.order_timestamp,
    o.order_date,
    o.order_status,
    o.order_channel,
    c.customer_id,
    c.customer_name,
    c.customer_tier,
    ci.city_name                                AS customer_city,
    r.restaurant_id,
    r.restaurant_name,
    r.cuisine_type,
    z.zone_name,
    o.subtotal_amount,
    o.discount_amount,
    o.delivery_fee,
    o.taxes,
    o.total_amount,
    o.platform_commission,
    o.payment_method,
    d.partner_id,
    dp.partner_name,
    d.actual_time_mins,
    d.expected_time_mins,
    d.distance_km,
    d.sla_breached,
    d.on_time,
    rv.food_rating,
    rv.delivery_rating,
    rv.overall_rating
FROM orders o
JOIN customers          c  ON o.customer_id    = c.customer_id
JOIN restaurants        r  ON o.restaurant_id  = r.restaurant_id
JOIN cities             ci ON c.city_id        = ci.city_id
LEFT JOIN zones         z  ON o.zone_id        = z.zone_id
LEFT JOIN deliveries    d  ON o.order_id       = d.order_id
LEFT JOIN delivery_partners dp ON d.partner_id = dp.partner_id
LEFT JOIN reviews       rv ON o.order_id       = rv.order_id;

COMMENT ON VIEW v_order_detail IS
    'Fully denormalised order view for ad-hoc analysis and BI tools.';

-- =============================================================================
-- MATERIALIZED VIEWS (pre-computed for performance)
-- =============================================================================

-- MV 1: Daily platform KPIs (refresh nightly)
CREATE MATERIALIZED VIEW mv_daily_kpi AS
SELECT
    order_date                                          AS day,
    EXTRACT(DOW FROM order_date)::INT                   AS day_of_week,
    TO_CHAR(order_date, 'Day')                         AS day_name,
    EXTRACT(HOUR FROM MIN(order_timestamp))::INT        AS peak_start_hour,
    COUNT(*)                                            AS total_orders,
    COUNT(*) FILTER (WHERE order_status = 'Delivered')  AS delivered_orders,
    COUNT(*) FILTER (WHERE order_status = 'Cancelled')  AS cancelled_orders,
    COUNT(DISTINCT customer_id)                         AS active_customers,
    COUNT(DISTINCT restaurant_id)                       AS active_restaurants,
    ROUND(SUM(total_amount)::numeric, 2)               AS gross_revenue,
    ROUND(SUM(platform_commission)::numeric, 2)        AS platform_revenue,
    ROUND(SUM(discount_amount)::numeric, 2)            AS discounts_given,
    ROUND(AVG(total_amount)::numeric, 2)               AS avg_order_value,
    ROUND(
        COUNT(*) FILTER (WHERE order_status = 'Cancelled')::numeric
        / NULLIF(COUNT(*), 0) * 100, 2
    )                                                   AS cancellation_rate_pct
FROM orders
GROUP BY order_date
ORDER BY order_date DESC;

CREATE UNIQUE INDEX idx_mv_daily_kpi_date ON mv_daily_kpi(day);
COMMENT ON MATERIALIZED VIEW mv_daily_kpi IS
    'Daily KPIs. Refresh nightly: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_kpi';

-- MV 2: Restaurant performance summary
CREATE MATERIALIZED VIEW mv_restaurant_performance AS
WITH order_stats AS (
    SELECT
        restaurant_id,
        COUNT(*)                                            AS total_orders,
        COUNT(*) FILTER (WHERE order_status = 'Delivered') AS delivered_orders,
        ROUND(SUM(total_amount)::numeric, 2)               AS gross_revenue,
        ROUND(SUM(platform_commission)::numeric, 2)        AS platform_revenue,
        ROUND(AVG(total_amount)::numeric, 2)               AS avg_order_value,
        COUNT(DISTINCT customer_id)                        AS unique_customers,
        MIN(order_timestamp)::date                         AS first_order_date,
        MAX(order_timestamp)::date                         AS last_order_date
    FROM orders
    WHERE order_status != 'Cancelled'
    GROUP BY restaurant_id
),
review_stats AS (
    SELECT
        restaurant_id,
        COUNT(*)                        AS review_count,
        ROUND(AVG(food_rating)::numeric, 2) AS avg_food_rating,
        ROUND(AVG(overall_rating)::numeric, 2) AS avg_overall_rating
    FROM reviews
    GROUP BY restaurant_id
)
SELECT
    r.restaurant_id,
    r.restaurant_name,
    r.cuisine_type,
    ci.city_name,
    r.rating,
    r.is_active,
    r.joining_date,
    os.total_orders,
    os.delivered_orders,
    os.gross_revenue,
    os.platform_revenue,
    os.avg_order_value,
    os.unique_customers,
    rs.review_count,
    rs.avg_food_rating,
    rs.avg_overall_rating,
    RANK() OVER (ORDER BY os.gross_revenue DESC NULLS LAST)        AS revenue_rank,
    RANK() OVER (
        PARTITION BY r.cuisine_type ORDER BY os.gross_revenue DESC NULLS LAST
    )                                                               AS cuisine_revenue_rank,
    ROUND(PERCENT_RANK() OVER (ORDER BY os.gross_revenue NULLS LAST) * 100, 1)
                                                                    AS revenue_percentile
FROM restaurants r
JOIN cities ci ON r.city_id = ci.city_id
LEFT JOIN order_stats os USING (restaurant_id)
LEFT JOIN review_stats rs USING (restaurant_id);

CREATE UNIQUE INDEX idx_mv_rest_perf_id ON mv_restaurant_performance(restaurant_id);
CREATE INDEX idx_mv_rest_perf_city  ON mv_restaurant_performance(city_name, revenue_rank);

-- MV 3: Hourly demand heatmap
CREATE MATERIALIZED VIEW mv_hourly_demand AS
SELECT
    EXTRACT(DOW FROM order_timestamp)::INT                  AS day_of_week,
    TO_CHAR(order_timestamp, 'Day')                        AS day_name,
    EXTRACT(HOUR FROM order_timestamp)::INT                 AS hour_of_day,
    COUNT(*)                                                AS order_count,
    ROUND(AVG(total_amount)::numeric, 2)                   AS avg_order_value,
    ROUND(SUM(total_amount)::numeric, 2)                   AS total_revenue,
    ROUND(
        COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 3
    )                                                       AS pct_of_total,
    ROUND(
        COUNT(*)::numeric / AVG(COUNT(*)) OVER (), 3
    )                                                       AS demand_index
FROM orders
WHERE order_status != 'Cancelled'
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX idx_mv_hourly_demand ON mv_hourly_demand(day_of_week, hour_of_day);

-- MV 4: Delivery partner performance
CREATE MATERIALIZED VIEW mv_partner_performance AS
SELECT
    dp.partner_id,
    dp.partner_name,
    dp.vehicle_type,
    ci.city_name,
    z.zone_name,
    dp.rating                                               AS partner_rating,
    dp.joining_date,
    COUNT(d.delivery_id)                                    AS total_deliveries,
    COUNT(*) FILTER (WHERE d.delivery_status = 'Delivered') AS completed_deliveries,
    ROUND(AVG(d.actual_time_mins)::numeric, 1)             AS avg_delivery_time,
    ROUND(AVG(d.distance_km)::numeric, 2)                  AS avg_distance_km,
    ROUND(SUM(d.partner_earnings)::numeric, 2)             AS total_earnings,
    COUNT(*) FILTER (WHERE d.sla_breached = TRUE)          AS sla_breaches,
    COUNT(*) FILTER (WHERE d.on_time = TRUE)               AS on_time_deliveries,
    ROUND(
        COUNT(*) FILTER (WHERE d.on_time = TRUE)::numeric
        / NULLIF(COUNT(*) FILTER (WHERE d.delivery_status = 'Delivered'), 0) * 100, 1
    )                                                       AS on_time_rate_pct,
    RANK() OVER (ORDER BY COUNT(d.delivery_id) DESC)       AS delivery_count_rank,
    NTILE(4) OVER (ORDER BY COUNT(d.delivery_id))          AS performance_quartile
FROM delivery_partners dp
JOIN cities ci ON dp.city_id = ci.city_id
LEFT JOIN zones z ON dp.zone_id = z.zone_id
LEFT JOIN deliveries d ON dp.partner_id = d.partner_id
WHERE dp.is_active = TRUE
GROUP BY dp.partner_id, dp.partner_name, dp.vehicle_type,
         ci.city_name, z.zone_name, dp.rating, dp.joining_date;

CREATE UNIQUE INDEX idx_mv_partner_perf_id ON mv_partner_performance(partner_id);

-- MV 5: Customer RFM segments (weekly refresh)
CREATE MATERIALIZED VIEW mv_customer_rfm AS
WITH rfm_base AS (
    SELECT
        customer_id,
        CURRENT_DATE - MAX(order_date)              AS recency_days,
        COUNT(DISTINCT order_id)                    AS frequency,
        ROUND(SUM(total_amount)::numeric, 2)        AS monetary
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency)          AS f_score,
        NTILE(5) OVER (ORDER BY monetary)           AS m_score
    FROM rfm_base
)
SELECT
    rs.customer_id,
    c.customer_name,
    c.customer_tier,
    rs.recency_days,
    rs.frequency,
    rs.monetary,
    rs.r_score, rs.f_score, rs.m_score,
    rs.r_score + rs.f_score + rs.m_score            AS rfm_total,
    CASE
        WHEN rs.r_score >= 4 AND rs.f_score >= 4 AND rs.m_score >= 4 THEN 'Champions'
        WHEN rs.r_score >= 3 AND rs.f_score >= 3                      THEN 'Loyal'
        WHEN rs.r_score >= 4 AND rs.f_score <= 2                      THEN 'Promising'
        WHEN rs.r_score = 5  AND rs.f_score = 1                       THEN 'New Customer'
        WHEN rs.r_score <= 2 AND rs.f_score >= 4                      THEN 'At Risk'
        WHEN rs.r_score = 1  AND rs.f_score = 1                       THEN 'Lost'
        ELSE 'Needs Attention'
    END                                              AS rfm_segment
FROM rfm_scored rs
JOIN customers c USING (customer_id);

CREATE UNIQUE INDEX idx_mv_rfm_customer ON mv_customer_rfm(customer_id);
CREATE INDEX idx_mv_rfm_segment ON mv_customer_rfm(rfm_segment);

-- Refresh procedure
CREATE OR REPLACE PROCEDURE refresh_all_views()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_kpi;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_restaurant_performance;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hourly_demand;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_partner_performance;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_customer_rfm;
    RAISE NOTICE 'All materialized views refreshed at %', CURRENT_TIMESTAMP;
END;
$$;
