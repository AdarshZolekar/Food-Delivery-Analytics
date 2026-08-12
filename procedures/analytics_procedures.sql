-- =============================================================================
-- FILE:        procedures/analytics_procedures.sql
-- =============================================================================

-- Generate a customer retention report for a given month
CREATE OR REPLACE FUNCTION fn_retention_report(p_year INT, p_month INT)
RETURNS TABLE(
    cohort_month    TEXT,
    cohort_size     BIGINT,
    retained_m1     BIGINT,
    retained_m3     BIGINT,
    retained_m6     BIGINT,
    retention_m1_pct NUMERIC,
    retention_m3_pct NUMERIC,
    retention_m6_pct NUMERIC
)
LANGUAGE sql STABLE AS $$
    WITH first_orders AS (
        SELECT customer_id,
               DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort_month
        FROM orders WHERE order_status = 'Delivered'
        GROUP BY customer_id
    ),
    activity AS (
        SELECT fo.customer_id, fo.cohort_month,
               DATE_TRUNC('month', o.order_timestamp)::date AS active_month
        FROM first_orders fo
        JOIN orders o USING (customer_id)
        WHERE o.order_status = 'Delivered'
    ),
    cohort_sizes AS (
        SELECT cohort_month, COUNT(*) AS cohort_size FROM first_orders GROUP BY 1
    )
    SELECT
        TO_CHAR(cs.cohort_month, 'YYYY-MM'),
        cs.cohort_size,
        COUNT(DISTINCT a1.customer_id),
        COUNT(DISTINCT a3.customer_id),
        COUNT(DISTINCT a6.customer_id),
        ROUND(COUNT(DISTINCT a1.customer_id)*100.0/cs.cohort_size,1),
        ROUND(COUNT(DISTINCT a3.customer_id)*100.0/cs.cohort_size,1),
        ROUND(COUNT(DISTINCT a6.customer_id)*100.0/cs.cohort_size,1)
    FROM cohort_sizes cs
    LEFT JOIN activity a1 ON cs.cohort_month = a1.cohort_month
        AND a1.active_month = cs.cohort_month + INTERVAL '1 month'
    LEFT JOIN activity a3 ON cs.cohort_month = a3.cohort_month
        AND a3.active_month = cs.cohort_month + INTERVAL '3 months'
    LEFT JOIN activity a6 ON cs.cohort_month = a6.cohort_month
        AND a6.active_month = cs.cohort_month + INTERVAL '6 months'
    WHERE EXTRACT(YEAR FROM cs.cohort_month) = p_year
      AND EXTRACT(MONTH FROM cs.cohort_month) = p_month
    GROUP BY cs.cohort_month, cs.cohort_size
    ORDER BY cs.cohort_month;
$$;


-- Delivery performance report by zone
CREATE OR REPLACE FUNCTION fn_delivery_performance_by_zone(
    p_start_date DATE DEFAULT CURRENT_DATE - 30,
    p_end_date   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    zone_name       TEXT,
    city_name       TEXT,
    total_deliveries BIGINT,
    avg_time_mins   NUMERIC,
    median_time_mins NUMERIC,
    sla_breach_pct  NUMERIC,
    on_time_pct     NUMERIC,
    avg_distance_km NUMERIC,
    total_earnings  NUMERIC
)
LANGUAGE sql STABLE AS $$
    SELECT
        z.zone_name,
        ci.city_name,
        COUNT(*),
        ROUND(AVG(d.actual_time_mins)::numeric, 1),
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.actual_time_mins)::numeric, 1),
        ROUND(COUNT(*) FILTER (WHERE d.sla_breached)*100.0/NULLIF(COUNT(*),0),1),
        ROUND(COUNT(*) FILTER (WHERE d.on_time)*100.0/NULLIF(COUNT(*),0),1),
        ROUND(AVG(d.distance_km)::numeric, 2),
        ROUND(SUM(d.partner_earnings)::numeric, 2)
    FROM deliveries d
    JOIN orders o ON d.order_id = o.order_id
    JOIN zones  z ON o.zone_id  = z.zone_id
    JOIN cities ci ON z.city_id = ci.city_id
    WHERE d.delivery_status = 'Delivered'
      AND o.order_date BETWEEN p_start_date AND p_end_date
    GROUP BY z.zone_name, ci.city_name
    ORDER BY COUNT(*) DESC;
$$;
