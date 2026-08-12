-- =============================================================================
-- FILE:        analytics/delivery_analytics.sql
-- Description: Delivery efficiency, SLA compliance, partner performance,
--              zone analysis, and operational bottleneck identification.
-- =============================================================================

-- =============================================================================
-- Q1: Delivery Time Distribution — Percentile Analysis
-- =============================================================================

SELECT
    ROUND(AVG(actual_time_mins)::numeric, 1)            AS mean_mins,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP
        (ORDER BY actual_time_mins)::numeric, 0)        AS p25_mins,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP
        (ORDER BY actual_time_mins)::numeric, 0)        AS median_mins,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP
        (ORDER BY actual_time_mins)::numeric, 0)        AS p75_mins,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP
        (ORDER BY actual_time_mins)::numeric, 0)        AS p90_mins,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP
        (ORDER BY actual_time_mins)::numeric, 0)        AS p95_mins,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP
        (ORDER BY actual_time_mins)::numeric, 0)        AS p99_mins,
    COUNT(*)                                            AS total_deliveries,
    COUNT(*) FILTER (WHERE sla_breached)                AS sla_breaches,
    ROUND(COUNT(*) FILTER (WHERE sla_breached) * 100.0
        / NULLIF(COUNT(*), 0)::numeric, 2)              AS sla_breach_pct,
    COUNT(*) FILTER (WHERE on_time)                     AS on_time_count,
    ROUND(COUNT(*) FILTER (WHERE on_time) * 100.0
        / NULLIF(COUNT(*), 0)::numeric, 2)              AS on_time_rate_pct
FROM deliveries
WHERE delivery_status = 'Delivered'
  AND actual_time_mins IS NOT NULL;


-- =============================================================================
-- Q2: Peak Hour Delivery Heatmap — Demand × Performance Matrix
-- =============================================================================

SELECT
    TO_CHAR(o.order_timestamp, 'Day')               AS day_name,
    EXTRACT(DOW FROM o.order_timestamp)::INT         AS day_num,
    EXTRACT(HOUR FROM o.order_timestamp)::INT        AS hour,
    COUNT(d.delivery_id)                            AS deliveries,
    ROUND(AVG(d.actual_time_mins)::numeric, 1)      AS avg_delivery_mins,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY d.actual_time_mins)::numeric, 0)  AS median_delivery_mins,
    COUNT(*) FILTER (WHERE d.sla_breached)          AS sla_breaches,
    ROUND(COUNT(*) FILTER (WHERE d.sla_breached) * 100.0
        / NULLIF(COUNT(*), 0)::numeric, 1)          AS sla_breach_pct,
    -- Congestion index
    ROUND(AVG(d.actual_time_mins) / AVG(AVG(d.actual_time_mins)) OVER ()
    ::numeric, 3)                                   AS congestion_index
FROM deliveries d
JOIN orders o ON d.order_id = o.order_id
WHERE d.delivery_status = 'Delivered'
  AND d.actual_time_mins IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY day_num, hour;


-- =============================================================================
-- Q3: Partner Performance Rankings with Scoring
-- =============================================================================

SELECT
    pp.partner_id,
    pp.partner_name,
    pp.vehicle_type,
    pp.city_name,
    pp.zone_name,
    pp.partner_rating,
    pp.total_deliveries,
    pp.completed_deliveries,
    pp.avg_delivery_time,
    pp.avg_distance_km,
    pp.total_earnings,
    pp.on_time_rate_pct,
    pp.sla_breaches,
    pp.delivery_count_rank,
    pp.performance_quartile,
    -- Composite score (0-100)
    ROUND(
        COALESCE(pp.partner_rating, 0)   * 20 +   -- 0-20: rating
        COALESCE(pp.on_time_rate_pct, 0) * 0.3 +  -- 0-30: on-time rate
        LEAST(25, pp.total_deliveries / 40.0) +   -- 0-25: experience
        GREATEST(0, 25 - COALESCE(pp.avg_delivery_time, 40))  -- 0-25: speed
    ::numeric, 1)                                 AS performance_score,
    CASE
        WHEN pp.performance_quartile = 4 THEN '🌟 Top Performer'
        WHEN pp.performance_quartile = 3 THEN '✅ Good'
        WHEN pp.performance_quartile = 2 THEN '📊 Average'
        ELSE                                   '⚠️  Needs Coaching'
    END                                           AS performance_tier
FROM mv_partner_performance pp
ORDER BY performance_score DESC NULLS LAST
LIMIT 100;


-- =============================================================================
-- Q4: Zone-Level SLA Analysis and Risk Identification
-- =============================================================================

WITH zone_stats AS (
    SELECT
        z.zone_id,
        z.zone_name,
        ci.city_name,
        z.avg_delivery_time_mins                    AS target_time,
        COUNT(d.delivery_id)                        AS total_deliveries,
        ROUND(AVG(d.actual_time_mins)::numeric, 1)  AS actual_avg_time,
        ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP
            (ORDER BY d.actual_time_mins)::numeric, 0) AS p90_time,
        COUNT(*) FILTER (WHERE d.sla_breached)      AS sla_breaches,
        ROUND(COUNT(*) FILTER (WHERE d.sla_breached) * 100.0
            / NULLIF(COUNT(*), 0)::numeric, 1)      AS sla_breach_pct,
        COUNT(DISTINCT d.partner_id)                AS active_partners
    FROM zones z
    JOIN cities ci ON z.city_id = ci.city_id
    LEFT JOIN orders o ON z.zone_id = o.zone_id
    LEFT JOIN deliveries d ON o.order_id = d.order_id
        AND d.delivery_status = 'Delivered'
    GROUP BY z.zone_id, z.zone_name, ci.city_name, z.avg_delivery_time_mins
    HAVING COUNT(d.delivery_id) > 100
)
SELECT
    zone_name, city_name, target_time,
    total_deliveries, active_partners,
    actual_avg_time, p90_time,
    sla_breach_pct,
    ROUND(actual_avg_time - target_time ::numeric, 1) AS time_vs_target_mins,
    -- Zone risk level
    CASE
        WHEN sla_breach_pct > 20 OR actual_avg_time > target_time * 1.5
        THEN '🚨 High Risk — Increase partner supply'
        WHEN sla_breach_pct > 10 OR actual_avg_time > target_time * 1.2
        THEN '⚠️  Medium Risk — Monitor closely'
        ELSE '✅ On Target'
    END                                             AS zone_risk,
    -- Partner density recommendation
    ROUND(total_deliveries::numeric / NULLIF(active_partners, 0), 1)
                                                    AS deliveries_per_partner
FROM zone_stats
ORDER BY sla_breach_pct DESC;


-- =============================================================================
-- Q5: Delivery Cancellation Root Cause Analysis
-- =============================================================================

SELECT
    o.cancellation_reason,
    COUNT(*)                                        AS cancellations,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () ::numeric, 2)
                                                    AS pct_of_cancellations,
    ROUND(AVG(o.total_amount)::numeric, 2)          AS avg_order_value_lost,
    ROUND(SUM(o.total_amount)::numeric, 2)          AS total_gmv_lost,
    -- Cancellation time analysis
    ROUND(AVG(
        CASE WHEN o.cancelled_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (o.cancelled_at - o.order_timestamp)) / 60
             ELSE NULL END
    )::numeric, 1)                                  AS avg_mins_before_cancel,
    -- Which hours see most cancellations?
    MODE() WITHIN GROUP (ORDER BY EXTRACT(HOUR FROM o.order_timestamp)::INT)
                                                    AS most_common_cancel_hour
FROM orders o
WHERE o.order_status = 'Cancelled'
  AND o.cancellation_reason IS NOT NULL
GROUP BY o.cancellation_reason
ORDER BY cancellations DESC;


-- =============================================================================
-- Q6: Delivery Partner Earnings and Utilisation
-- =============================================================================

WITH daily_partner AS (
    SELECT
        d.partner_id,
        o.order_date,
        COUNT(*)                        AS deliveries_that_day,
        SUM(d.partner_earnings)         AS earnings_that_day,
        SUM(d.distance_km)              AS km_that_day,
        AVG(d.actual_time_mins)         AS avg_time_that_day
    FROM deliveries d
    JOIN orders o ON d.order_id = o.order_id
    WHERE d.delivery_status = 'Delivered'
    GROUP BY d.partner_id, o.order_date
)
SELECT
    dp.partner_id,
    dp.partner_name,
    dp.vehicle_type,
    ci.city_name,
    COUNT(DISTINCT dp2.order_date)              AS working_days,
    ROUND(AVG(dp2.deliveries_that_day)::numeric,1) AS avg_deliveries_per_day,
    ROUND(SUM(dp2.earnings_that_day)::numeric,2)   AS total_earnings,
    ROUND(AVG(dp2.earnings_that_day)::numeric,2)   AS avg_daily_earnings,
    ROUND(SUM(dp2.km_that_day)::numeric,1)         AS total_km,
    ROUND(AVG(dp2.avg_time_that_day)::numeric,1)   AS avg_delivery_time,
    -- Utilisation: partners doing 8+ deliveries/day are considered fully utilised
    ROUND(
        COUNT(DISTINCT dp2.order_date) FILTER (WHERE dp2.deliveries_that_day >= 8)
        * 100.0 / NULLIF(COUNT(DISTINCT dp2.order_date), 0)
    ::numeric, 1)                               AS high_util_days_pct
FROM delivery_partners dp
JOIN cities ci ON dp.city_id = ci.city_id
JOIN daily_partner dp2 ON dp.partner_id = dp2.partner_id
WHERE dp.is_active = TRUE
GROUP BY dp.partner_id, dp.partner_name, dp.vehicle_type, ci.city_name
ORDER BY total_earnings DESC
LIMIT 50;
