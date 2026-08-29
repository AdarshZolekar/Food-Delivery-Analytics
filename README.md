# Food Delivery Analytics System 

<div align="center">

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14%2B-336791?style=for-the-badge&logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12%2B-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Analytics](https://img.shields.io/badge/Analytics-Moderate-orange?style=for-the-badge)
![Tests](https://img.shields.io/badge/Tests-pytest-green?style=for-the-badge)

**An end-to-end food delivery analytics platform modelled on Swiggy / Zomato / DoorDash operations. Covers restaurant intelligence, customer retention science, real-time delivery tracking and executive BI — powered by PostgreSQL, Python and Power BI.**

[ Analytics](#analytics-layer) · [ Delivery Intelligence](#delivery-intelligence) · [ Retention Analysis](#customer-retention) · [ Quick Start](#quick-start) · [ Skills](#skills-demonstrated)

</div>

---

## Table of Contents

- [Business Problem](#-business-problem)
- [Platform Architecture](#-platform-architecture)
- [Database Design](#-database-design)
- [ER Diagram](#-er-diagram)
- [Analytics Layer](#-analytics-layer)
- [Customer Retention](#-customer-retention)
- [Delivery Intelligence](#-delivery-intelligence)
- [Quick Start](#-quick-start)
- [Project Structure](#-project-structure)
- [Skills Demonstrated](#-skills-demonstrated)

---

## Business Problem

**SwiftEats** is a food delivery platform operating across 20 cities with 5,000+ restaurant partners. The analytics team needs to answer:

- *"Why are customers churning after their 3rd order?"*
- *"Which zones have unacceptable delivery SLA breaches?"*
- *"What is the true Customer Lifetime Value by acquisition channel?"*
- *"Which restaurants are growth engines vs. declining partners?"*
- *"When exactly is the dinner rush and how do we staff for it?"*

---

## Platform Architecture

```mermaid
flowchart TD
    subgraph Sources[" Platform Sources"]
        APP[Mobile App / Web]
        REST[Restaurant Portal]
        PARTNER[Delivery App]
        SUPPORT[Support System]
    end

    subgraph Core[" Core Database (PostgreSQL)"]
        ORDERS[Orders + Items]
        CUST[Customers]
        REST_DB[Restaurants + Menus]
        DELIVERY[Deliveries + Partners]
        PAYMENTS[Payments + Promotions]
        REVIEWS[Reviews + Ratings]
        TICKETS[Support Tickets]
    end

    subgraph Analytics[" Analytics Layer"]
        VIEWS[Materialized Views]
        PROCS[Stored Procedures]
        TRIGGERS[Business Triggers]
    end

    subgraph BI[" BI & Insights"]
        EXEC[Executive Dashboard]
        OPS[Ops Dashboard]
        NB[Jupyter Notebooks]
        SQL[Ad-hoc Analytics]
    end

    Sources --> Core
    Core --> Analytics
    Analytics --> BI
```

---

## Database Design

**15 production tables** across 5 business domains:

### Order Domain
| Table | Rows | Description |
|-------|------|-------------|
| `orders` | 1,000,000+ | Order lifecycle from placement to delivery |
| `order_items` | 2,500,000+ | Line items (avg 2.5 items per order) |
| `order_status_history` | 4,000,000+ | Full audit trail of every status change |

### Customer Domain
| Table | Rows | Description |
|-------|------|-------------|
| `customers` | 100,000 | Customer profiles with tier classification |
| `customer_addresses` | 130,000 | Saved delivery addresses |

### Restaurant Domain
| Table | Rows | Description |
|-------|------|-------------|
| `restaurants` | 5,000 | Restaurant profiles with cuisine and ratings |
| `menu_categories` | 25,000 | Category hierarchy per restaurant |
| `menu_items` | 150,000 | Full item catalog with pricing |

### Delivery Domain
| Table | Rows | Description |
|-------|------|-------------|
| `delivery_partners` | 10,000 | Partner profiles and performance |
| `deliveries` | 900,000 | Delivery tracking with timing data |
| `zones` | 200 | Delivery zone boundaries |
| `cities` | 20 | Operating city reference data |

### Platform Domain
| Table | Rows | Description |
|-------|------|-------------|
| `payments` | 1,000,000 | Payment transactions |
| `promotions` | 500 | Discount codes and offers |
| `reviews` | 750,000 | Food and delivery ratings |
| `support_tickets` | 80,000 | Customer support lifecycle |

---

## ER Diagram

```mermaid
erDiagram
    CITIES {
        int city_id PK
        varchar city_name
        varchar state
        varchar country
        varchar timezone
    }
    ZONES {
        int zone_id PK
        int city_id FK
        varchar zone_name
        numeric lat
        numeric lng
    }
    RESTAURANTS {
        int restaurant_id PK
        int city_id FK
        int zone_id FK
        varchar name
        varchar cuisine_type
        numeric rating
        numeric commission_rate
        bool is_active
    }
    MENU_ITEMS {
        int item_id PK
        int restaurant_id FK
        int category_id FK
        varchar item_name
        numeric price
        bool is_available
        bool is_vegetarian
    }
    CUSTOMERS {
        int customer_id PK
        int city_id FK
        varchar customer_name
        varchar email
        varchar tier
        date registration_date
        bool is_active
    }
    DELIVERY_PARTNERS {
        int partner_id PK
        int city_id FK
        int zone_id FK
        varchar partner_name
        varchar vehicle_type
        numeric rating
        int total_deliveries
    }
    ORDERS {
        int order_id PK
        int customer_id FK
        int restaurant_id FK
        int zone_id FK
        int promotion_id FK
        timestamptz order_timestamp
        varchar order_status
        numeric total_amount
        numeric discount_amount
        numeric delivery_fee
    }
    ORDER_ITEMS {
        int order_item_id PK
        int order_id FK
        int item_id FK
        int quantity
        numeric unit_price
        numeric item_total
    }
    DELIVERIES {
        int delivery_id PK
        int order_id FK
        int partner_id FK
        timestamptz assigned_at
        timestamptz delivered_at
        int actual_time_mins
        int expected_time_mins
        numeric distance_km
        varchar delivery_status
    }
    PAYMENTS {
        int payment_id PK
        int order_id FK
        numeric amount
        varchar method
        varchar status
        timestamptz payment_timestamp
    }
    REVIEWS {
        int review_id PK
        int order_id FK
        int customer_id FK
        int restaurant_id FK
        smallint food_rating
        smallint delivery_rating
        text review_text
    }
    PROMOTIONS {
        int promotion_id PK
        varchar promo_code
        varchar promo_type
        numeric discount_value
        date end_date
        bool is_active
    }
    SUPPORT_TICKETS {
        int ticket_id PK
        int customer_id FK
        int order_id FK
        varchar issue_type
        varchar status
        varchar priority
    }

    CITIES ||--o{ ZONES : "contains"
    CITIES ||--o{ RESTAURANTS : "located_in"
    CITIES ||--o{ CUSTOMERS : "lives_in"
    CITIES ||--o{ DELIVERY_PARTNERS : "operates_in"
    ZONES ||--o{ ORDERS : "delivered_to"
    RESTAURANTS ||--o{ MENU_ITEMS : "offers"
    RESTAURANTS ||--o{ ORDERS : "receives"
    RESTAURANTS ||--o{ REVIEWS : "rated_in"
    CUSTOMERS ||--o{ ORDERS : "places"
    CUSTOMERS ||--o{ REVIEWS : "writes"
    CUSTOMERS ||--o{ SUPPORT_TICKETS : "raises"
    ORDERS ||--o{ ORDER_ITEMS : "contains"
    ORDERS ||--o{ DELIVERIES : "fulfilled_by"
    ORDERS ||--o{ PAYMENTS : "paid_via"
    ORDERS ||--o{ REVIEWS : "generates"
    DELIVERY_PARTNERS ||--o{ DELIVERIES : "handles"
    MENU_ITEMS ||--o{ ORDER_ITEMS : "sold_in"
    PROMOTIONS ||--o{ ORDERS : "applied_to"
```

---

## Analytics Layer

### Peak Order Time Analysis
```sql
-- Dinner rush heatmap: orders by day × hour
SELECT
    TO_CHAR(order_timestamp, 'Day')          AS day_name,
    EXTRACT(HOUR FROM order_timestamp)::INT  AS hour_of_day,
    COUNT(*)                                 AS orders,
    ROUND(AVG(total_amount)::numeric, 2)     AS avg_order_value,
    -- Demand index: how many times busier than average hour
    ROUND(COUNT(*) * 1.0 /
        AVG(COUNT(*)) OVER ()::numeric, 2)   AS demand_index
FROM orders
WHERE order_status != 'CANCELLED'
GROUP BY 1, 2
ORDER BY demand_index DESC;
```

### Customer Cohort Retention
```sql
WITH first_order AS (
    SELECT customer_id,
           DATE_TRUNC('month', MIN(order_timestamp))::date AS cohort_month
    FROM orders GROUP BY 1
),
monthly_activity AS (
    SELECT fo.customer_id, fo.cohort_month,
           DATE_TRUNC('month', o.order_timestamp)::date AS active_month,
           (EXTRACT(YEAR FROM AGE(
               DATE_TRUNC('month', o.order_timestamp),
               fo.cohort_month::timestamp)) * 12 +
            EXTRACT(MONTH FROM AGE(
               DATE_TRUNC('month', o.order_timestamp),
               fo.cohort_month::timestamp)))::INT AS months_since_join
    FROM first_order fo JOIN orders o USING (customer_id)
)
SELECT TO_CHAR(cohort_month, 'YYYY-MM') AS cohort,
       months_since_join AS month_number,
       COUNT(DISTINCT customer_id) AS active_customers
FROM monthly_activity
WHERE months_since_join <= 6
GROUP BY 1, 2 ORDER BY cohort_month, months_since_join;
```

---

## Delivery Intelligence

Key metrics and targets:

| Metric | Target | Alert Threshold |
|--------|--------|----------------|
| Avg Delivery Time | ≤ 30 min | > 45 min |
| SLA Compliance | ≥ 90% | < 80% |
| On-Time Rate | ≥ 85% | < 75% |
| Partner Utilisation | 6–8 orders/day | < 4 orders/day |
| Cancellation Rate | ≤ 3% | > 6% |
| Avg Food Rating | ≥ 4.2/5 | < 3.8/5 |

---

## Quick Start

### Option A — Docker
```bash
git clone https://github.com/AdarshZolekar/Food-Delivery-Analytics.git
cd Food-Delivery-Analytics
cp .env.example .env
docker-compose -f docker/docker-compose.yml up -d
python scripts/setup_database.py
python data/generate_data.py
python scripts/load_data.py
```

### Option B — Local PostgreSQL
```bash
pip install -r requirements.txt
cp .env.example .env   # Edit DB credentials
python scripts/setup_database.py
python data/generate_data.py
python scripts/load_data.py
python scripts/run_analytics.py
jupyter lab notebooks/
```

---

## Project Structure

```
Food-Delivery-Analytics/
├── schema/              SQL DDL: 15 tables, 30+ indexes, 7 triggers
├── data/                Python data generator (1M+ orders, 100K customers)
├── procedures/          Stored procedures for order, delivery, analytics
├── analytics/           Advanced SQL: retention, delivery, restaurant, BI
├── dashboards/          Power BI specs, KPI dictionary, DAX measures
├── notebooks/           4 Jupyter notebooks for interactive analysis
├── scripts/             One-command setup and ETL
├── tests/               pytest suite with 60+ test cases
└── docker/              Full-stack local deployment.
```

---

## Skills Demonstrated

<details>
<summary><strong>SQL & Database Engineering</strong></summary>

- 15-table normalized schema (3NF) with referential integrity
- Window functions: ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD
- CTEs, recursive CTEs, correlated subqueries
- Cohort retention analysis from scratch
- RFM customer segmentation
- Moving averages and running totals for time-series
- Materialized views for pre-computed KPIs
- Partitioning strategy for orders by month
- BRIN indexes for timestamp columns (5× speedup).

</details>

<details>
<summary><strong>Product Analytics</strong></summary>

- Peak demand heatmaps (hour × day matrix)
- Customer churn prediction features
- Delivery SLA compliance tracking
- Restaurant performance scoring
- Promotion effectiveness analysis (lift vs. baseline)
- Zone-level operational intelligence.

</details>

<details>
<summary><strong>Python Engineering</strong></summary>

- OOP data generator with realistic seasonal distributions
- Configurable via environment variables
- Structured logging throughout
- Type hints and docstrings on all classes/functions
- 60+ pytest test cases covering business rules.

</details>

---

## Performance Results

| Query | Without Optimisation | With Optimisation | Speedup |
|-------|---------------------|-------------------|---------|
| Customer order history | 380 ms | 1.1 ms | **345×** |
| Monthly revenue rollup | 2.1 s | 0.05 s | **42×** |
| Delivery time analysis | 1.8 s | 0.12 s | **15×** |
| RFM segmentation | 4.2 s | 0.8 s | **5.3×** |
| Peak hour heatmap | 3.1 s | 0.03 s | **103×** |

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## Contributions

Contributions are welcome!

- Open an issue for bugs or feature requests

- Submit a pull request for improvements.

<p align="center">
  <a href="#top">
    <img src="https://img.shields.io/badge/%E2%AC%86-Back%20to%20Top-blue?style=for-the-badge" alt="Back to Top"/>
  </a>
</p>

