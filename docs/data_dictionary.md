# Data Dictionary

## Table: orders

| Column | Type | Description |
|--------|------|-------------|
| order_id | SERIAL PK | Auto-incrementing order identifier |
| customer_id | INT FK | References customers(customer_id) |
| restaurant_id | INT FK | References restaurants(restaurant_id) |
| zone_id | INT FK | Delivery zone (for SLA tracking) |
| promotion_id | INT FK | Applied promo code (nullable) |
| order_timestamp | TIMESTAMPTZ | When order was placed (with timezone) |
| order_status | VARCHAR(30) | State machine: Placed→Confirmed→Preparing→Ready→Picked Up→On The Way→Delivered or Cancelled |
| subtotal_amount | NUMERIC(10,2) | Sum of order_items.item_total |
| discount_amount | NUMERIC(8,2) | Discount from promotion |
| delivery_fee | NUMERIC(6,2) | Delivery charge to customer |
| taxes | NUMERIC(8,2) | GST at 5% of (subtotal - discount) |
| total_amount | NUMERIC(10,2) | subtotal - discount + delivery_fee + taxes |
| platform_commission | NUMERIC(8,2) | total_amount × restaurant.commission_rate / 100 |
| order_date | DATE | GENERATED: order_timestamp::date (for partitioning) |

## Table: deliveries

| Column | Type | Description |
|--------|------|-------------|
| delivery_id | SERIAL PK | |
| order_id | INT FK | One delivery per order (standard flow) |
| partner_id | INT FK | Assigned delivery partner |
| actual_time_mins | INT | Elapsed minutes from order_timestamp to delivered_at |
| expected_time_mins | INT | Zone's avg_delivery_time_mins at assignment time |
| sla_breached | BOOLEAN | GENERATED: actual_time_mins > 45 |
| on_time | BOOLEAN | GENERATED: actual_time_mins <= expected_time_mins |
| partner_earnings | NUMERIC(6,2) | delivery_fee × 0.7 + distance_km × ₹2 |

## Table: reviews

| Column | Type | Description |
|--------|------|-------------|
| food_rating | SMALLINT | 1–5 stars for food quality |
| delivery_rating | SMALLINT | 1–5 stars for delivery experience |
| overall_rating | SMALLINT | Holistic 1–5 rating (drives restaurant.rating) |
| is_verified | BOOLEAN | TRUE when reviewer has a delivered order |

## Materialized View: mv_customer_rfm

| Column | Description |
|--------|-------------|
| r_score | Recency quintile (5=ordered most recently) |
| f_score | Frequency quintile (5=most orders) |
| m_score | Monetary quintile (5=highest spend) |
| rfm_segment | Named segment: Champions / Loyal / Promising / New Customer / At Risk / Hibernating / Lost |
| rfm_total | r_score + f_score + m_score (3–15) |

## Enum Values

**order_status:** Placed, Confirmed, Preparing, Ready, Picked Up, On The Way, Delivered, Cancelled

**delivery_status:** Pending, Assigned, En Route to Restaurant, Picked Up, En Route to Customer, Delivered, Failed, Cancelled

**vehicle_type:** Bicycle, Motorbike, Scooter, Car

**customer_tier:** Bronze (<₹2K), Silver (₹2K–5K), Gold (₹5K–10K), Platinum (>₹10K lifetime spend)

**promo_type:** FLAT (fixed ₹ off), PERCENT (% off up to max_discount), FREE_DELIVERY (zeroes delivery_fee), BOGO (buy one get one)
