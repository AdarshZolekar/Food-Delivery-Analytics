-- =============================================================================
-- FILE:        analytics/interview_queries.sql
-- Description: 45 SQL interview questions with solutions, mapped to the
--              food delivery schema. Difficulty: Easy / Medium / Hard.
--              Mirrors real Data Analyst and Data Engineer interview rounds
--              at Swiggy, Zomato, DoorDash, Uber, Google, and Meta.
-- =============================================================================

/*
╔════════════════════════════════════════╗
║  EASY  (Q1 – Q15)                      ║
║  SELECT, WHERE, GROUP BY, basic JOINs  ║
╚════════════════════════════════════════╝
*/

-- Q1 [Easy] — How many orders were placed in each city last month?
SELECT ci.city_name, COUNT(o.order_id) AS order_count
FROM orders o
JOIN customers c  ON o.customer_id = c.customer_id
JOIN cities   ci  ON c.city_id     = ci.city_id
WHERE o.order_date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
  AND o.order_date <  DATE_TRUNC('month', CURRENT_DATE)
GROUP BY ci.city_name
ORDER BY order_count DESC;


-- Q2 [Easy] — Find all restaurants with a rating above 4.5 that are still active.
SELECT restaurant_id, restaurant_name, cuisine_type, rating, total_orders
FROM restaurants
WHERE rating > 4.5 AND is_active = TRUE
ORDER BY rating DESC;


-- Q3 [Easy] — What is the average order value by payment method?
SELECT payment_method,
       COUNT(*)                            AS orders,
       ROUND(AVG(total_amount)::numeric,2) AS avg_order_value,
       ROUND(SUM(total_amount)::numeric,2) AS total_revenue
FROM orders
WHERE order_status = 'Delivered'
GROUP BY payment_method
ORDER BY avg_order_value DESC;


-- Q4 [Easy] — List customers who have never placed an order.
SELECT c.customer_id, c.customer_name, c.email, c.registration_date
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL
ORDER BY c.registration_date DESC;


-- Q5 [Easy] — What are the top 10 most ordered menu items platform-wide?
SELECT mi.item_name, r.restaurant_name, r.cuisine_type,
       SUM(oi.quantity)            AS total_quantity_ordered,
       COUNT(DISTINCT oi.order_id) AS orders_containing_item
FROM order_items oi
JOIN menu_items  mi ON oi.item_id       = mi.item_id
JOIN restaurants r  ON mi.restaurant_id = r.restaurant_id
GROUP BY mi.item_name, r.restaurant_name, r.cuisine_type
ORDER BY total_quantity_ordered DESC
LIMIT 10;


-- Q6 [Easy] — How many delivery partners does each city have, broken down by vehicle?
SELECT ci.city_name, dp.vehicle_type,
       COUNT(*)                         AS partner_count,
       COUNT(*) FILTER (WHERE is_active) AS active_partners
FROM delivery_partners dp
JOIN cities ci ON dp.city_id = ci.city_id
GROUP BY ci.city_name, dp.vehicle_type
ORDER BY ci.city_name, partner_count DESC;


-- Q7 [Easy] — What is the cancellation rate per cuisine type?
SELECT r.cuisine_type,
       COUNT(o.order_id)                                    AS total_orders,
       COUNT(o.order_id) FILTER (WHERE o.order_status = 'Cancelled')
                                                            AS cancellations,
       ROUND(COUNT(o.order_id) FILTER (WHERE o.order_status = 'Cancelled')
           * 100.0 / NULLIF(COUNT(o.order_id), 0)::numeric, 2)
                                                            AS cancel_rate_pct
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
GROUP BY r.cuisine_type
ORDER BY cancel_rate_pct DESC;


-- Q8 [Easy] — Find all orders that took more than 45 minutes to deliver (SLA breach).
SELECT o.order_id, c.customer_name, r.restaurant_name,
       ci.city_name, z.zone_name,
       d.actual_time_mins,
       d.expected_time_mins,
       d.actual_time_mins - d.expected_time_mins AS overrun_mins
FROM deliveries d
JOIN orders      o  ON d.order_id     = o.order_id
JOIN customers   c  ON o.customer_id  = c.customer_id
JOIN restaurants r  ON o.restaurant_id = r.restaurant_id
JOIN cities      ci ON r.city_id      = ci.city_id
LEFT JOIN zones  z  ON o.zone_id      = z.zone_id
WHERE d.sla_breached = TRUE
ORDER BY d.actual_time_mins DESC
LIMIT 20;


-- Q9 [Easy] — What percentage of orders use a promotional code?
SELECT
    COUNT(*) FILTER (WHERE promotion_id IS NOT NULL) AS promo_orders,
    COUNT(*)                                          AS total_orders,
    ROUND(
        COUNT(*) FILTER (WHERE promotion_id IS NOT NULL) * 100.0
        / NULLIF(COUNT(*), 0)::numeric, 2
    )                                                 AS promo_usage_pct
FROM orders;


-- Q10 [Easy] — List restaurants that joined in the last 3 months and have > 100 orders.
SELECT r.restaurant_id, r.restaurant_name, r.cuisine_type,
       ci.city_name, r.joining_date, r.total_orders, r.rating
FROM restaurants r
JOIN cities ci ON r.city_id = ci.city_id
WHERE r.joining_date >= CURRENT_DATE - INTERVAL '3 months'
  AND r.total_orders > 100
ORDER BY r.total_orders DESC;


-- Q11 [Easy] — What is the average food rating by cuisine type?
SELECT r.cuisine_type,
       ROUND(AVG(rv.food_rating)::numeric, 2)    AS avg_food_rating,
       ROUND(AVG(rv.delivery_rating)::numeric, 2) AS avg_delivery_rating,
       COUNT(rv.review_id)                        AS review_count
FROM reviews rv
JOIN restaurants r ON rv.restaurant_id = r.restaurant_id
GROUP BY r.cuisine_type
HAVING COUNT(rv.review_id) >= 50
ORDER BY avg_food_rating DESC;


-- Q12 [Easy] — Which hours of the day have the highest order volume?
SELECT EXTRACT(HOUR FROM order_timestamp)::INT AS hour,
       COUNT(*)                                AS order_count,
       ROUND(AVG(total_amount)::numeric, 2)    AS avg_order_value
FROM orders
WHERE order_status != 'Cancelled'
GROUP BY 1
ORDER BY order_count DESC;


-- Q13 [Easy] — Find customers who spent more than ₹10,000 in the last 30 days.
SELECT c.customer_id, c.customer_name, c.customer_tier,
       COUNT(o.order_id)                      AS orders_last_30d,
       ROUND(SUM(o.total_amount)::numeric, 2) AS spend_last_30d
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_date >= CURRENT_DATE - 30
  AND o.order_status = 'Delivered'
GROUP BY c.customer_id, c.customer_name, c.customer_tier
HAVING SUM(o.total_amount) > 10000
ORDER BY spend_last_30d DESC;


-- Q14 [Easy] — Show support ticket distribution by issue type and status.
SELECT issue_type, status, COUNT(*) AS tickets,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY issue_type)
       ::numeric, 1) AS pct_within_type
FROM support_tickets
GROUP BY issue_type, status
ORDER BY issue_type, tickets DESC;


-- Q15 [Easy] — Find restaurants with no reviews yet.
SELECT r.restaurant_id, r.restaurant_name, r.cuisine_type,
       ci.city_name, r.joining_date, r.total_orders
FROM restaurants r
JOIN cities ci ON r.city_id = ci.city_id
LEFT JOIN reviews rv ON r.restaurant_id = rv.restaurant_id
WHERE rv.review_id IS NULL AND r.is_active = TRUE
ORDER BY r.total_orders DESC;


/*
╔═══════════════════════════════════════════════════════════╗
║  MEDIUM  (Q16 – Q35)                                       ║
║  Subqueries, CTEs, Window Functions, HAVING, multi-table  ║
╚═══════════════════════════════════════════════════════════╝
*/

-- Q16 [Medium] — Rank restaurants by revenue within each city.
WITH rest_revenue AS (
    SELECT r.restaurant_id, r.restaurant_name, ci.city_name,
           ROUND(SUM(o.total_amount)::numeric, 2) AS revenue
    FROM orders o
    JOIN restaurants r ON o.restaurant_id = r.restaurant_id
    JOIN cities ci ON r.city_id = ci.city_id
    WHERE o.order_status = 'Delivered'
    GROUP BY r.restaurant_id, r.restaurant_name, ci.city_name
)
SELECT city_name, restaurant_name, revenue,
       RANK() OVER (PARTITION BY city_name ORDER BY revenue DESC) AS city_rank,
       DENSE_RANK() OVER (ORDER BY revenue DESC)                  AS overall_dense_rank
FROM rest_revenue
ORDER BY city_name, city_rank;


-- Q17 [Medium] — Find the second most popular cuisine in each city by order count.
WITH cuisine_orders AS (
    SELECT ci.city_name, r.cuisine_type, COUNT(o.order_id) AS orders,
           RANK() OVER (PARTITION BY ci.city_name
                        ORDER BY COUNT(o.order_id) DESC) AS rk
    FROM orders o
    JOIN restaurants r ON o.restaurant_id = r.restaurant_id
    JOIN cities ci ON r.city_id = ci.city_id
    WHERE o.order_status = 'Delivered'
    GROUP BY ci.city_name, r.cuisine_type
)
SELECT city_name, cuisine_type, orders AS second_place_orders
FROM cuisine_orders WHERE rk = 2
ORDER BY city_name;


-- Q18 [Medium] — Calculate the 7-day moving average of daily orders.
WITH daily AS (
    SELECT order_date, COUNT(*) AS daily_orders
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY order_date
)
SELECT order_date, daily_orders,
       ROUND(AVG(daily_orders) OVER (
           ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       )::numeric, 1) AS ma_7day,
       ROUND(AVG(daily_orders) OVER (
           ORDER BY order_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       )::numeric, 1) AS ma_30day
FROM daily ORDER BY order_date DESC LIMIT 90;


-- Q19 [Medium] — Find customers who ordered from 5+ different cuisines (food explorers).
SELECT c.customer_id, c.customer_name, c.customer_tier,
       COUNT(DISTINCT r.cuisine_type) AS unique_cuisines_tried,
       COUNT(DISTINCT o.restaurant_id) AS unique_restaurants,
       COUNT(DISTINCT o.order_id)      AS total_orders
FROM orders o
JOIN customers   c ON o.customer_id   = c.customer_id
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
GROUP BY c.customer_id, c.customer_name, c.customer_tier
HAVING COUNT(DISTINCT r.cuisine_type) >= 5
ORDER BY unique_cuisines_tried DESC;


-- Q20 [Medium] — Month-over-month GMV growth with LAG.
WITH monthly_gmv AS (
    SELECT DATE_TRUNC('month', order_timestamp)::date AS month,
           ROUND(SUM(total_amount)::numeric, 2)       AS gmv
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY 1
)
SELECT month, gmv,
       LAG(gmv) OVER (ORDER BY month) AS prev_gmv,
       ROUND((gmv - LAG(gmv) OVER (ORDER BY month))
           / NULLIF(LAG(gmv) OVER (ORDER BY month), 0) * 100
       ::numeric, 1) AS mom_growth_pct,
       ROUND(SUM(gmv) OVER (ORDER BY month ROWS UNBOUNDED PRECEDING)::numeric, 2)
                                                      AS cumulative_gmv
FROM monthly_gmv ORDER BY month DESC;


-- Q21 [Medium] — Find delivery partners who completed 500+ deliveries with rating ≥ 4.5.
SELECT dp.partner_name, dp.vehicle_type, ci.city_name,
       dp.rating, dp.total_deliveries, dp.total_earnings
FROM delivery_partners dp
JOIN cities ci ON dp.city_id = ci.city_id
WHERE dp.total_deliveries >= 500 AND dp.rating >= 4.5
ORDER BY dp.total_deliveries DESC;


-- Q22 [Medium] — For each restaurant, find the hour that generates the most orders.
WITH hourly_orders AS (
    SELECT o.restaurant_id,
           EXTRACT(HOUR FROM o.order_timestamp)::INT AS hour,
           COUNT(*) AS orders,
           ROW_NUMBER() OVER (PARTITION BY o.restaurant_id
                              ORDER BY COUNT(*) DESC) AS rn
    FROM orders o
    WHERE o.order_status = 'Delivered'
    GROUP BY o.restaurant_id, EXTRACT(HOUR FROM o.order_timestamp)
)
SELECT r.restaurant_name, r.cuisine_type,
       ho.hour || ':00' AS peak_hour, ho.orders AS peak_hour_orders
FROM hourly_orders ho
JOIN restaurants r USING (restaurant_id)
WHERE ho.rn = 1
ORDER BY ho.orders DESC LIMIT 20;


-- Q23 [Medium] — Customers who placed orders in every month of the last 6 months.
WITH months AS (
    SELECT GENERATE_SERIES(
        DATE_TRUNC('month', CURRENT_DATE - INTERVAL '5 months'),
        DATE_TRUNC('month', CURRENT_DATE),
        '1 month'
    )::date AS month
),
customer_months AS (
    SELECT customer_id,
           DATE_TRUNC('month', order_timestamp)::date AS order_month
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY 1, 2
)
SELECT c.customer_id, c.customer_name, c.customer_tier,
       COUNT(DISTINCT cm.order_month) AS active_months
FROM customers c
JOIN customer_months cm USING (customer_id)
WHERE cm.order_month IN (SELECT month FROM months)
GROUP BY c.customer_id, c.customer_name, c.customer_tier
HAVING COUNT(DISTINCT cm.order_month) = 6
ORDER BY active_months DESC;


-- Q24 [Medium] — Running total of platform revenue with 30-day comparison.
WITH daily_rev AS (
    SELECT order_date,
           ROUND(SUM(platform_commission)::numeric, 2) AS platform_rev
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY order_date
)
SELECT order_date, platform_rev,
       ROUND(SUM(platform_rev) OVER (
           ORDER BY order_date ROWS UNBOUNDED PRECEDING
       )::numeric, 2)                       AS running_total,
       ROUND(SUM(platform_rev) OVER (
           ORDER BY order_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       )::numeric, 2)                       AS rolling_30d_rev,
       LAG(platform_rev, 30) OVER (ORDER BY order_date) AS same_day_30d_ago,
       ROUND(
           (platform_rev - LAG(platform_rev, 30) OVER (ORDER BY order_date))
           / NULLIF(LAG(platform_rev, 30) OVER (ORDER BY order_date), 0) * 100
       ::numeric, 1)                        AS growth_vs_30d_ago_pct
FROM daily_rev ORDER BY order_date DESC LIMIT 60;


-- Q25 [Medium] — Find orders where the customer spent more than their average.
SELECT o.order_id, c.customer_name,
       o.total_amount       AS this_order,
       cust_avg.avg_spend   AS customer_avg,
       ROUND(o.total_amount - cust_avg.avg_spend ::numeric, 2) AS above_avg_by
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN (
    SELECT customer_id, AVG(total_amount) AS avg_spend
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
) cust_avg USING (customer_id)
WHERE o.order_status = 'Delivered'
  AND o.total_amount > cust_avg.avg_spend * 1.5
ORDER BY above_avg_by DESC LIMIT 20;


-- Q26 [Medium] — Identify restaurants whose ratings improved vs 3 months ago.
WITH monthly_ratings AS (
    SELECT rv.restaurant_id,
           DATE_TRUNC('month', rv.created_at)::date AS month,
           ROUND(AVG(rv.food_rating)::numeric, 2)   AS avg_rating
    FROM reviews rv GROUP BY 1, 2
)
SELECT r.restaurant_name, r.cuisine_type, ci.city_name,
       current_m.avg_rating  AS current_rating,
       prior_3m.avg_rating   AS rating_3m_ago,
       ROUND(current_m.avg_rating - prior_3m.avg_rating ::numeric, 2) AS improvement
FROM monthly_ratings current_m
JOIN monthly_ratings prior_3m
    ON  current_m.restaurant_id = prior_3m.restaurant_id
    AND current_m.month = DATE_TRUNC('month', CURRENT_DATE)::date
    AND prior_3m.month  = (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '3 months')::date
JOIN restaurants r  ON current_m.restaurant_id = r.restaurant_id
JOIN cities      ci ON r.city_id = ci.city_id
WHERE current_m.avg_rating > prior_3m.avg_rating
ORDER BY improvement DESC;


-- Q27 [Medium] — NTILE: Bucket customers into spending quintiles.
WITH customer_spend AS (
    SELECT customer_id, SUM(total_amount) AS total_spent
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    NTILE(5) OVER (ORDER BY total_spent) AS quintile,
    COUNT(*)                            AS customers,
    ROUND(MIN(total_spent)::numeric, 2) AS min_spend,
    ROUND(MAX(total_spent)::numeric, 2) AS max_spend,
    ROUND(AVG(total_spent)::numeric, 2) AS avg_spend,
    ROUND(SUM(total_spent)::numeric, 2) AS total_revenue
FROM customer_spend
GROUP BY NTILE(5) OVER (ORDER BY total_spent)
ORDER BY quintile;


-- Q28 [Medium] — Find the longest streak of consecutive days with orders for each restaurant.
WITH daily_orders AS (
    SELECT restaurant_id, order_date,
           order_date - (ROW_NUMBER() OVER (
               PARTITION BY restaurant_id ORDER BY order_date
           ) * INTERVAL '1 day')::date AS grp
    FROM (SELECT DISTINCT restaurant_id, order_date FROM orders
          WHERE order_status = 'Delivered') t
)
SELECT r.restaurant_name, MAX(streak) AS longest_streak_days
FROM (
    SELECT restaurant_id, COUNT(*) AS streak FROM daily_orders GROUP BY restaurant_id, grp
) streaks
JOIN restaurants r USING (restaurant_id)
GROUP BY r.restaurant_name
ORDER BY longest_streak_days DESC LIMIT 10;


-- Q29 [Medium] — Compare weekday vs weekend performance per restaurant.
SELECT r.restaurant_name,
       ROUND(AVG(o.total_amount) FILTER (
           WHERE EXTRACT(DOW FROM o.order_timestamp) NOT IN (0,6)
       )::numeric, 2)                           AS weekday_aov,
       ROUND(AVG(o.total_amount) FILTER (
           WHERE EXTRACT(DOW FROM o.order_timestamp) IN (0,6)
       )::numeric, 2)                           AS weekend_aov,
       COUNT(*) FILTER (
           WHERE EXTRACT(DOW FROM o.order_timestamp) NOT IN (0,6)
       )                                        AS weekday_orders,
       COUNT(*) FILTER (
           WHERE EXTRACT(DOW FROM o.order_timestamp) IN (0,6)
       )                                        AS weekend_orders
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
GROUP BY r.restaurant_name
HAVING COUNT(*) > 100
ORDER BY weekend_aov - weekday_aov DESC NULLS LAST
LIMIT 20;


-- Q30 [Medium] — FIRST_VALUE and LAST_VALUE: First and last order per customer.
SELECT DISTINCT
    c.customer_id,
    c.customer_name,
    FIRST_VALUE(o.order_timestamp) OVER w  AS first_order_time,
    FIRST_VALUE(r.restaurant_name) OVER w  AS first_restaurant,
    LAST_VALUE(o.order_timestamp) OVER w   AS last_order_time,
    LAST_VALUE(r.restaurant_name) OVER w   AS last_restaurant,
    COUNT(*) OVER (PARTITION BY c.customer_id) AS total_orders
FROM orders o
JOIN customers   c ON o.customer_id   = c.customer_id
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
WINDOW w AS (
    PARTITION BY c.customer_id ORDER BY o.order_timestamp
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
LIMIT 20;


/*
╔═══════════════════════════════════════════════════════════╗
║  HARD  (Q31 – Q45)                                         ║
║  Cohort analysis, recursive CTEs, complex window funcs    ║
╚═══════════════════════════════════════════════════════════╝
*/

-- Q31 [Hard] — Full cohort retention matrix (M0–M6).
-- (See analytics/customer_analytics.sql Q1 for full implementation)
WITH first_order AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort
    FROM orders WHERE order_status = 'Delivered' GROUP BY 1
),
sizes AS (SELECT cohort, COUNT(*) AS sz FROM first_order GROUP BY 1),
activity AS (
    SELECT fo.customer_id, fo.cohort,
           (EXTRACT(YEAR FROM AGE(DATE_TRUNC('month',o.order_timestamp), fo.cohort::TIMESTAMP))*12
           + EXTRACT(MONTH FROM AGE(DATE_TRUNC('month',o.order_timestamp), fo.cohort::TIMESTAMP)))::INT AS mn
    FROM first_order fo JOIN orders o USING (customer_id)
    WHERE o.order_status = 'Delivered'
)
SELECT TO_CHAR(a.cohort,'YYYY-MM') AS cohort, s.sz AS cohort_size,
       ROUND(COUNT(DISTINCT a.customer_id) FILTER (WHERE mn=0)*100.0/s.sz,1) AS m0,
       ROUND(COUNT(DISTINCT a.customer_id) FILTER (WHERE mn=1)*100.0/s.sz,1) AS m1,
       ROUND(COUNT(DISTINCT a.customer_id) FILTER (WHERE mn=3)*100.0/s.sz,1) AS m3,
       ROUND(COUNT(DISTINCT a.customer_id) FILTER (WHERE mn=6)*100.0/s.sz,1) AS m6
FROM activity a JOIN sizes s USING (cohort)
GROUP BY a.cohort, s.sz
ORDER BY a.cohort;


-- Q32 [Hard] — Identify delivery partners who are underperforming in their zone.
WITH zone_avg AS (
    SELECT o.zone_id,
           AVG(d.actual_time_mins) AS zone_avg_time,
           AVG(d.partner_earnings) AS zone_avg_earnings
    FROM deliveries d JOIN orders o USING (order_id)
    WHERE d.delivery_status = 'Delivered'
    GROUP BY o.zone_id
),
partner_stats AS (
    SELECT d.partner_id, o.zone_id,
           AVG(d.actual_time_mins) AS partner_avg_time,
           COUNT(*) AS deliveries
    FROM deliveries d JOIN orders o USING (order_id)
    WHERE d.delivery_status = 'Delivered'
    GROUP BY d.partner_id, o.zone_id
    HAVING COUNT(*) >= 20
)
SELECT dp.partner_name, dp.vehicle_type, z.zone_name,
       ROUND(ps.partner_avg_time::numeric,1) AS partner_avg_mins,
       ROUND(za.zone_avg_time::numeric,1)    AS zone_avg_mins,
       ROUND(ps.partner_avg_time - za.zone_avg_time::numeric, 1) AS mins_above_zone_avg,
       ps.deliveries
FROM partner_stats ps
JOIN zone_avg za ON ps.zone_id = za.zone_id
JOIN delivery_partners dp ON ps.partner_id = dp.partner_id
JOIN zones z ON ps.zone_id = z.zone_id
WHERE ps.partner_avg_time > za.zone_avg_time * 1.3
ORDER BY mins_above_zone_avg DESC;


-- Q33 [Hard] — Customer LTV segmentation with future value projection.
WITH customer_metrics AS (
    SELECT o.customer_id,
           COUNT(DISTINCT o.order_id)                   AS orders,
           ROUND(SUM(o.total_amount)::numeric,2)        AS ltv,
           ROUND(AVG(o.total_amount)::numeric,2)        AS aov,
           MIN(o.order_timestamp)::date                 AS first_order,
           MAX(o.order_timestamp)::date                 AS last_order,
           CURRENT_DATE - MIN(o.order_timestamp)::date  AS age_days
    FROM orders o WHERE o.order_status = 'Delivered'
    GROUP BY o.customer_id
),
with_scores AS (
    SELECT *,
        ROUND(orders::numeric / NULLIF(age_days / 30.0, 0), 2) AS orders_per_month,
        NTILE(5) OVER (ORDER BY ltv DESC) AS ltv_quintile
    FROM customer_metrics
)
SELECT
    ltv_quintile,
    COUNT(*)                                        AS customers,
    ROUND(AVG(ltv)::numeric, 2)                     AS avg_ltv,
    ROUND(SUM(ltv)::numeric, 2)                     AS total_revenue,
    ROUND(AVG(orders)::numeric, 1)                  AS avg_orders,
    ROUND(AVG(aov)::numeric, 2)                     AS avg_aov,
    ROUND(AVG(orders_per_month)::numeric, 2)        AS avg_orders_per_month,
    -- Projected 12-month value
    ROUND(AVG(orders_per_month) * 12 * AVG(aov)::numeric, 2) AS projected_12m_ltv
FROM with_scores
GROUP BY ltv_quintile
ORDER BY ltv_quintile;


-- Q34 [Hard] — Find restaurants where revenue is declining 3 months in a row.
WITH monthly_rev AS (
    SELECT restaurant_id,
           DATE_TRUNC('month', order_timestamp)::date AS month,
           SUM(total_amount) AS revenue
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY 1, 2
),
with_trend AS (
    SELECT *,
        LAG(revenue,1) OVER (PARTITION BY restaurant_id ORDER BY month) AS m1,
        LAG(revenue,2) OVER (PARTITION BY restaurant_id ORDER BY month) AS m2,
        LAG(revenue,3) OVER (PARTITION BY restaurant_id ORDER BY month) AS m3
    FROM monthly_rev
)
SELECT r.restaurant_name, r.cuisine_type, ci.city_name,
       t.month, t.revenue AS current_revenue,
       t.m1 AS prev_1m, t.m2 AS prev_2m, t.m3 AS prev_3m
FROM with_trend t
JOIN restaurants r ON t.restaurant_id = r.restaurant_id
JOIN cities ci ON r.city_id = ci.city_id
WHERE t.revenue < t.m1
  AND t.m1 < t.m2
  AND t.m2 < t.m3
  AND t.month = DATE_TRUNC('month', CURRENT_DATE)::date
ORDER BY t.revenue / NULLIF(t.m3, 0);


-- Q35 [Hard] — Median order value by city and day of week (PERCENTILE_CONT).
SELECT
    ci.city_name,
    EXTRACT(DOW FROM o.order_timestamp)::INT        AS dow,
    TO_CHAR(o.order_timestamp, 'Day')               AS day_name,
    COUNT(*)                                        AS orders,
    ROUND(AVG(o.total_amount)::numeric,2)           AS mean_aov,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY o.total_amount)::numeric, 2)      AS median_aov,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP
        (ORDER BY o.total_amount)::numeric, 2)      AS p75_aov,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP
        (ORDER BY o.total_amount)::numeric, 2)      AS p90_aov
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN cities ci ON c.city_id = ci.city_id
WHERE o.order_status = 'Delivered'
GROUP BY ci.city_name, EXTRACT(DOW FROM o.order_timestamp), TO_CHAR(o.order_timestamp,'Day')
ORDER BY ci.city_name, dow;


-- Q36 [Hard] — RFM Full Segmentation with Revenue Attribution.
-- (see schema/views.sql mv_customer_rfm + analytics/customer_analytics.sql Q2)


-- Q37 [Hard] — Calculate day-over-day order growth rate for the past 90 days.
WITH daily AS (
    SELECT order_date, COUNT(*) AS orders
    FROM orders WHERE order_status = 'Delivered'
      AND order_date >= CURRENT_DATE - 90
    GROUP BY order_date
)
SELECT order_date, orders,
       LAG(orders) OVER (ORDER BY order_date) AS prev_day_orders,
       ROUND((orders - LAG(orders) OVER (ORDER BY order_date))
           / NULLIF(LAG(orders) OVER (ORDER BY order_date), 0) * 100
       ::numeric, 2) AS dod_growth_pct,
       -- 7-day MA
       ROUND(AVG(orders) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
       ::numeric, 1) AS ma_7d
FROM daily ORDER BY order_date DESC;


-- Q38 [Hard] — Find customers who increased their order frequency in Q2 vs Q1.
WITH quarterly AS (
    SELECT customer_id,
           COUNT(*) FILTER (WHERE EXTRACT(QUARTER FROM order_timestamp) = 1
               AND EXTRACT(YEAR FROM order_timestamp) = EXTRACT(YEAR FROM CURRENT_DATE))
                                    AS q1_orders,
           COUNT(*) FILTER (WHERE EXTRACT(QUARTER FROM order_timestamp) = 2
               AND EXTRACT(YEAR FROM order_timestamp) = EXTRACT(YEAR FROM CURRENT_DATE))
                                    AS q2_orders
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
    HAVING COUNT(*) FILTER (WHERE EXTRACT(QUARTER FROM order_timestamp) IN (1,2)) > 0
)
SELECT c.customer_name, c.customer_tier,
       q.q1_orders, q.q2_orders,
       q.q2_orders - q.q1_orders AS improvement
FROM quarterly q
JOIN customers c USING (customer_id)
WHERE q.q2_orders > q.q1_orders
ORDER BY improvement DESC LIMIT 20;


-- Q39 [Hard] — ABC inventory analysis for menu items.
WITH item_revenue AS (
    SELECT oi.item_id, SUM(oi.item_total) AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY oi.item_id
),
abc AS (
    SELECT item_id, revenue,
        ROUND(SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
            / NULLIF(SUM(revenue) OVER (), 0) * 100 ::numeric, 2) AS cumulative_pct
    FROM item_revenue
)
SELECT mi.item_name, r.restaurant_name,
       ROUND(abc.revenue::numeric,2) AS revenue,
       abc.cumulative_pct,
       CASE WHEN cumulative_pct <= 80 THEN 'A - Core (top 80%)'
            WHEN cumulative_pct <= 95 THEN 'B - Important (80-95%)'
            ELSE 'C - Long Tail' END AS abc_class
FROM abc
JOIN menu_items  mi ON abc.item_id = mi.item_id
JOIN restaurants r  ON mi.restaurant_id = r.restaurant_id
ORDER BY revenue DESC LIMIT 50;


-- Q40 [Hard] — Identify zones with consistent demand spikes on Fridays.
WITH friday_vs_avg AS (
    SELECT o.zone_id,
           EXTRACT(DOW FROM o.order_timestamp) AS dow,
           COUNT(*) AS orders
    FROM orders o WHERE o.order_status = 'Delivered'
    GROUP BY o.zone_id, EXTRACT(DOW FROM o.order_timestamp)
),
zone_stats AS (
    SELECT zone_id,
           MAX(orders) FILTER (WHERE dow = 5)               AS friday_orders,
           AVG(orders)                                       AS avg_all_day
    FROM friday_vs_avg GROUP BY zone_id
)
SELECT z.zone_name, ci.city_name,
       zs.friday_orders,
       ROUND(zs.avg_all_day::numeric, 0) AS avg_daily_orders,
       ROUND(zs.friday_orders / NULLIF(zs.avg_all_day, 0)::numeric, 2) AS friday_spike
FROM zone_stats zs
JOIN zones z ON zs.zone_id = z.zone_id
JOIN cities ci ON z.city_id = ci.city_id
WHERE zs.friday_orders > zs.avg_all_day * 1.3
ORDER BY friday_spike DESC;


-- Q41 [Hard] — Partner churn analysis: partners who stopped delivering.
WITH last_delivery AS (
    SELECT partner_id, MAX(delivered_at)::date AS last_active_date
    FROM deliveries WHERE delivery_status = 'Delivered'
    GROUP BY partner_id
)
SELECT dp.partner_name, dp.vehicle_type, ci.city_name,
       dp.joining_date, ld.last_active_date,
       CURRENT_DATE - ld.last_active_date AS days_inactive,
       dp.total_deliveries,
       CASE
           WHEN CURRENT_DATE - ld.last_active_date > 60 THEN 'Churned'
           WHEN CURRENT_DATE - ld.last_active_date > 30 THEN 'At Risk'
           ELSE 'Active'
       END AS partner_status
FROM delivery_partners dp
JOIN cities ci ON dp.city_id = ci.city_id
LEFT JOIN last_delivery ld ON dp.partner_id = ld.partner_id
WHERE dp.is_active = TRUE
  AND (ld.last_active_date < CURRENT_DATE - 30 OR ld.last_active_date IS NULL)
ORDER BY days_inactive DESC NULLS FIRST;


-- Q42 [Hard] — Cross-sell analysis: what do customers order alongside Pizza?
WITH pizza_orders AS (
    SELECT DISTINCT oi.order_id
    FROM order_items oi
    JOIN menu_items mi ON oi.item_id = mi.item_id
    JOIN restaurants r ON mi.restaurant_id = r.restaurant_id
    WHERE r.cuisine_type = 'Pizza'
),
co_ordered AS (
    SELECT mi.item_name, r.cuisine_type,
           COUNT(DISTINCT oi.order_id) AS co_order_count
    FROM order_items oi
    JOIN menu_items  mi ON oi.item_id = mi.item_id
    JOIN restaurants r  ON mi.restaurant_id = r.restaurant_id
    WHERE oi.order_id IN (SELECT order_id FROM pizza_orders)
      AND r.cuisine_type != 'Pizza'
    GROUP BY mi.item_name, r.cuisine_type
)
SELECT item_name, cuisine_type, co_order_count
FROM co_ordered ORDER BY co_order_count DESC LIMIT 15;


-- Q43 [Hard] — Rolling 30-day customer retention rate.
WITH daily_new AS (
    SELECT DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort_month,
           customer_id
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
daily_active AS (
    SELECT order_date, COUNT(DISTINCT customer_id) AS active_customers
    FROM orders WHERE order_status = 'Delivered'
    GROUP BY order_date
),
retained AS (
    SELECT o.order_date,
           COUNT(DISTINCT o.customer_id) FILTER (
               WHERE dn.cohort_month < DATE_TRUNC('month', o.order_date)
           ) AS returning_customers,
           COUNT(DISTINCT o.customer_id) AS total_active
    FROM orders o LEFT JOIN daily_new dn ON o.customer_id = dn.customer_id
    WHERE o.order_status = 'Delivered'
    GROUP BY o.order_date
)
SELECT order_date,
       returning_customers,
       total_active,
       ROUND(returning_customers * 100.0 / NULLIF(total_active,0)::numeric,1) AS retention_rate_pct,
       ROUND(AVG(returning_customers * 100.0 / NULLIF(total_active,0)) OVER (
           ORDER BY order_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       )::numeric,1) AS rolling_30d_retention_pct
FROM retained ORDER BY order_date DESC LIMIT 60;


-- Q44 [Hard] — Geospatial proxy: zones farthest from city center (high lat/lng).
WITH zone_distance AS (
    SELECT z.zone_id, z.zone_name, ci.city_name,
           AVG(d.actual_time_mins)   AS avg_delivery_time,
           AVG(d.distance_km)        AS avg_distance,
           COUNT(d.delivery_id)      AS deliveries
    FROM zones z
    JOIN orders o ON z.zone_id = o.zone_id
    JOIN deliveries d ON o.order_id = d.order_id
    JOIN cities ci ON z.city_id = ci.city_id
    WHERE d.delivery_status = 'Delivered'
    GROUP BY z.zone_id, z.zone_name, ci.city_name
)
SELECT zone_name, city_name,
       ROUND(avg_delivery_time::numeric,1) AS avg_mins,
       ROUND(avg_distance::numeric,2)      AS avg_km,
       deliveries,
       RANK() OVER (PARTITION BY city_name ORDER BY avg_delivery_time DESC) AS slow_rank
FROM zone_distance
ORDER BY avg_delivery_time DESC LIMIT 20;


-- Q45 [Hard] — Platform GMV at risk: orders with no delivery partner assigned.
SELECT
    COUNT(*) FILTER (WHERE o.order_status NOT IN ('Delivered','Cancelled')
        AND d.delivery_id IS NULL)              AS unassigned_active_orders,
    ROUND(SUM(o.total_amount) FILTER (
        WHERE o.order_status NOT IN ('Delivered','Cancelled')
        AND d.delivery_id IS NULL)::numeric, 2) AS gmv_at_risk,
    -- By zone
    z.zone_name,
    ci.city_name
FROM orders o
LEFT JOIN deliveries d ON o.order_id = d.order_id
LEFT JOIN zones z  ON o.zone_id = z.zone_id
LEFT JOIN cities ci ON z.city_id = ci.city_id
WHERE o.order_status NOT IN ('Delivered', 'Cancelled')
GROUP BY z.zone_name, ci.city_name
HAVING COUNT(*) FILTER (WHERE d.delivery_id IS NULL) > 0
ORDER BY gmv_at_risk DESC;
