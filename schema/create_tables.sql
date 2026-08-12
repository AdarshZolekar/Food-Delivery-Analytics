-- =============================================================================
-- FILE:        schema/create_tables.sql
-- Description: All 15 core tables for the food delivery platform.
-- Target:      PostgreSQL 14+
-- =============================================================================

-- =============================================================================
-- REFERENCE / LOOKUP TABLES
-- =============================================================================

CREATE TABLE cities (
    city_id         SERIAL          PRIMARY KEY,
    city_name       VARCHAR(100)    NOT NULL,
    state           VARCHAR(100)    NOT NULL,
    country         VARCHAR(50)     NOT NULL DEFAULT 'India',
    timezone        VARCHAR(50)     NOT NULL DEFAULT 'Asia/Kolkata',
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    launch_date     DATE
);
COMMENT ON TABLE cities IS 'Operating cities. Core reference table.';

CREATE TABLE zones (
    zone_id         SERIAL          PRIMARY KEY,
    city_id         INT             NOT NULL REFERENCES cities(city_id),
    zone_name       VARCHAR(100)    NOT NULL,
    zone_code       VARCHAR(20),
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6),
    avg_delivery_time_mins INT      DEFAULT 25,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE zones IS 'Delivery zones within cities. Used for demand mapping and partner assignment.';

-- =============================================================================
-- RESTAURANT DOMAIN
-- =============================================================================

CREATE TABLE restaurants (
    restaurant_id       SERIAL          PRIMARY KEY,
    restaurant_name     VARCHAR(200)    NOT NULL,
    cuisine_type        VARCHAR(50)     NOT NULL,
    city_id             INT             NOT NULL REFERENCES cities(city_id),
    zone_id             INT             REFERENCES zones(zone_id),
    owner_name          VARCHAR(100),
    phone               VARCHAR(20),
    email               VARCHAR(100),
    address             TEXT,
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    rating              NUMERIC(3,2)    DEFAULT 0.00
                                        CHECK (rating BETWEEN 0 AND 5),
    total_ratings       INT             NOT NULL DEFAULT 0,
    avg_delivery_time_mins INT          DEFAULT 30,
    min_order_amount    NUMERIC(8,2)    DEFAULT 0.00,
    commission_rate     NUMERIC(5,2)    DEFAULT 20.00
                                        CHECK (commission_rate BETWEEN 5 AND 40),
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    is_pure_veg         BOOLEAN         NOT NULL DEFAULT FALSE,
    joining_date        DATE            NOT NULL DEFAULT CURRENT_DATE,
    total_orders        INT             NOT NULL DEFAULT 0,
    total_revenue       NUMERIC(14,2)   NOT NULL DEFAULT 0.00
);
COMMENT ON TABLE restaurants IS 'Restaurant partner profiles. rating and totals are updated by triggers.';

CREATE TABLE menu_categories (
    category_id     SERIAL          PRIMARY KEY,
    restaurant_id   INT             NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
    category_name   VARCHAR(100)    NOT NULL,
    display_order   INT             DEFAULT 0,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE TABLE menu_items (
    item_id         SERIAL          PRIMARY KEY,
    restaurant_id   INT             NOT NULL REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
    category_id     INT             REFERENCES menu_categories(category_id),
    item_name       VARCHAR(200)    NOT NULL,
    description     TEXT,
    price           NUMERIC(8,2)    NOT NULL CHECK (price > 0),
    is_available    BOOLEAN         NOT NULL DEFAULT TRUE,
    is_vegetarian   BOOLEAN         NOT NULL DEFAULT FALSE,
    calories        INT             CHECK (calories > 0),
    preparation_time_mins INT       DEFAULT 15,
    is_bestseller   BOOLEAN         NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE menu_items IS 'Full item catalog. price is the current selling price.';

-- =============================================================================
-- CUSTOMER DOMAIN
-- =============================================================================

CREATE TABLE customers (
    customer_id         SERIAL          PRIMARY KEY,
    customer_name       VARCHAR(100)    NOT NULL,
    email               VARCHAR(100)    NOT NULL,
    phone               VARCHAR(20),
    city_id             INT             REFERENCES cities(city_id),
    registration_date   TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_order_date     TIMESTAMPTZ,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    customer_tier       VARCHAR(20)     NOT NULL DEFAULT 'Bronze'
                                        CHECK (customer_tier IN ('Bronze','Silver','Gold','Platinum')),
    total_orders        INT             NOT NULL DEFAULT 0,
    total_spent         NUMERIC(12,2)   NOT NULL DEFAULT 0.00,
    referral_code       VARCHAR(20),
    acquisition_channel VARCHAR(50)     DEFAULT 'Organic'
);
COMMENT ON TABLE customers IS 'Customer profiles. tier and totals updated by triggers on order completion.';

CREATE TABLE customer_addresses (
    address_id      SERIAL          PRIMARY KEY,
    customer_id     INT             NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    address_label   VARCHAR(30)     DEFAULT 'Home'
                                    CHECK (address_label IN ('Home','Work','Other')),
    street_address  VARCHAR(200),
    area            VARCHAR(100),
    city_id         INT             REFERENCES cities(city_id),
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6),
    is_default      BOOLEAN         NOT NULL DEFAULT FALSE
);

-- =============================================================================
-- DELIVERY DOMAIN
-- =============================================================================

CREATE TABLE delivery_partners (
    partner_id          SERIAL          PRIMARY KEY,
    partner_name        VARCHAR(100)    NOT NULL,
    phone               VARCHAR(20)     NOT NULL,
    email               VARCHAR(100),
    city_id             INT             NOT NULL REFERENCES cities(city_id),
    zone_id             INT             REFERENCES zones(zone_id),
    vehicle_type        VARCHAR(30)     NOT NULL
                                        CHECK (vehicle_type IN ('Bicycle','Motorbike','Scooter','Car')),
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    current_status      VARCHAR(20)     NOT NULL DEFAULT 'Offline'
                                        CHECK (current_status IN ('Offline','Available','On Delivery')),
    rating              NUMERIC(3,2)    DEFAULT 0.00 CHECK (rating BETWEEN 0 AND 5),
    total_deliveries    INT             NOT NULL DEFAULT 0,
    total_earnings      NUMERIC(12,2)   NOT NULL DEFAULT 0.00,
    joining_date        DATE            NOT NULL DEFAULT CURRENT_DATE,
    bg_verification     BOOLEAN         NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE delivery_partners IS 'Delivery partner profiles. Ratings and totals updated by triggers.';

-- =============================================================================
-- PROMOTIONS (must exist before orders for FK)
-- =============================================================================

CREATE TABLE promotions (
    promotion_id        SERIAL          PRIMARY KEY,
    promo_code          VARCHAR(30)     NOT NULL UNIQUE,
    promo_name          VARCHAR(100),
    promo_type          VARCHAR(30)     NOT NULL
                                        CHECK (promo_type IN ('FLAT','PERCENT','FREE_DELIVERY','BOGO')),
    discount_value      NUMERIC(8,2)    NOT NULL CHECK (discount_value > 0),
    min_order_amount    NUMERIC(8,2)    NOT NULL DEFAULT 0,
    max_discount        NUMERIC(8,2),
    max_uses            INT,
    current_uses        INT             NOT NULL DEFAULT 0,
    start_date          DATE            NOT NULL,
    end_date            DATE            NOT NULL,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    applicable_to       VARCHAR(30)     DEFAULT 'ALL'
                                        CHECK (applicable_to IN ('ALL','NEW_USER','EXISTING','SPECIFIC_REST')),
    CHECK (end_date > start_date)
);

-- =============================================================================
-- ORDER DOMAIN
-- =============================================================================

CREATE TABLE orders (
    order_id            SERIAL          PRIMARY KEY,
    customer_id         INT             NOT NULL REFERENCES customers(customer_id),
    restaurant_id       INT             NOT NULL REFERENCES restaurants(restaurant_id),
    address_id          INT             REFERENCES customer_addresses(address_id),
    zone_id             INT             REFERENCES zones(zone_id),
    promotion_id        INT             REFERENCES promotions(promotion_id),
    order_timestamp     TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    confirmed_at        TIMESTAMPTZ,
    prepared_at         TIMESTAMPTZ,
    picked_up_at        TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    order_status        VARCHAR(30)     NOT NULL DEFAULT 'Placed'
                                        CHECK (order_status IN (
                                            'Placed','Confirmed','Preparing','Ready',
                                            'Picked Up','On The Way','Delivered','Cancelled'
                                        )),
    order_channel       VARCHAR(20)     NOT NULL DEFAULT 'App'
                                        CHECK (order_channel IN ('App','Web','Phone')),
    subtotal_amount     NUMERIC(10,2)   NOT NULL DEFAULT 0.00,
    discount_amount     NUMERIC(8,2)    NOT NULL DEFAULT 0.00,
    delivery_fee        NUMERIC(6,2)    NOT NULL DEFAULT 0.00,
    taxes               NUMERIC(8,2)    NOT NULL DEFAULT 0.00,
    total_amount        NUMERIC(10,2)   NOT NULL DEFAULT 0.00,
    platform_commission NUMERIC(8,2)    NOT NULL DEFAULT 0.00,
    payment_method      VARCHAR(30)     DEFAULT 'UPI'
                                        CHECK (payment_method IN (
                                            'UPI','Credit Card','Debit Card','Cash','Wallet','NetBanking'
                                        )),
    is_refunded         BOOLEAN         NOT NULL DEFAULT FALSE,
    refund_amount       NUMERIC(8,2)    DEFAULT 0.00,
    cancellation_reason VARCHAR(100),
    special_instructions TEXT,
    order_date          DATE            GENERATED ALWAYS AS (order_timestamp::date) STORED
);
COMMENT ON TABLE orders IS 'Order header. Grain: one customer order. Partitioned by order_date.';

-- Partition orders by month for performance
-- (Create partitions in generate_data.py for the appropriate date range)

CREATE TABLE order_items (
    order_item_id   SERIAL          PRIMARY KEY,
    order_id        INT             NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    item_id         INT             NOT NULL REFERENCES menu_items(item_id),
    quantity        INT             NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(8,2)    NOT NULL CHECK (unit_price > 0),
    item_total      NUMERIC(10,2)   GENERATED ALWAYS AS (quantity * unit_price) STORED,
    special_notes   TEXT
);
COMMENT ON TABLE order_items IS 'Order line items. item_total is GENERATED (qty × price).';

CREATE TABLE deliveries (
    delivery_id             SERIAL          PRIMARY KEY,
    order_id                INT             NOT NULL REFERENCES orders(order_id),
    partner_id              INT             REFERENCES delivery_partners(partner_id),
    assigned_at             TIMESTAMPTZ,
    restaurant_reached_at   TIMESTAMPTZ,
    picked_up_at            TIMESTAMPTZ,
    delivered_at            TIMESTAMPTZ,
    expected_delivery_time  TIMESTAMPTZ,
    actual_time_mins        INT,
    expected_time_mins      INT             DEFAULT 30,
    distance_km             NUMERIC(6,2),
    delivery_fee            NUMERIC(6,2),
    delivery_status         VARCHAR(30)     NOT NULL DEFAULT 'Pending'
                                            CHECK (delivery_status IN (
                                                'Pending','Assigned','En Route to Restaurant',
                                                'Picked Up','En Route to Customer',
                                                'Delivered','Failed','Cancelled'
                                            )),
    sla_breached            BOOLEAN         GENERATED ALWAYS AS
                                            (actual_time_mins > 45) STORED,
    on_time                 BOOLEAN         GENERATED ALWAYS AS
                                            (actual_time_mins <= expected_time_mins) STORED,
    delivery_rating         SMALLINT        CHECK (delivery_rating BETWEEN 1 AND 5),
    partner_earnings        NUMERIC(6,2)
);
COMMENT ON TABLE deliveries IS 'Delivery tracking. sla_breached and on_time are GENERATED columns.';

CREATE TABLE payments (
    payment_id          SERIAL          PRIMARY KEY,
    order_id            INT             NOT NULL REFERENCES orders(order_id),
    amount              NUMERIC(10,2)   NOT NULL CHECK (amount > 0),
    payment_method      VARCHAR(30)     NOT NULL,
    payment_status      VARCHAR(20)     NOT NULL DEFAULT 'Pending'
                                        CHECK (payment_status IN (
                                            'Pending','Completed','Failed','Refunded','Partially Refunded'
                                        )),
    transaction_id      VARCHAR(100)    UNIQUE,
    payment_timestamp   TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    refund_amount       NUMERIC(8,2)    DEFAULT 0.00,
    refund_timestamp    TIMESTAMPTZ,
    gateway_response    JSONB
);

CREATE TABLE reviews (
    review_id           SERIAL          PRIMARY KEY,
    order_id            INT             NOT NULL REFERENCES orders(order_id),
    customer_id         INT             NOT NULL REFERENCES customers(customer_id),
    restaurant_id       INT             NOT NULL REFERENCES restaurants(restaurant_id),
    partner_id          INT             REFERENCES delivery_partners(partner_id),
    food_rating         SMALLINT        NOT NULL CHECK (food_rating BETWEEN 1 AND 5),
    delivery_rating     SMALLINT        CHECK (delivery_rating BETWEEN 1 AND 5),
    overall_rating      SMALLINT        CHECK (overall_rating BETWEEN 1 AND 5),
    review_text         TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_verified         BOOLEAN         NOT NULL DEFAULT TRUE,
    helpful_votes       INT             NOT NULL DEFAULT 0,
    UNIQUE (order_id, customer_id)
);

CREATE TABLE support_tickets (
    ticket_id           SERIAL          PRIMARY KEY,
    customer_id         INT             NOT NULL REFERENCES customers(customer_id),
    order_id            INT             REFERENCES orders(order_id),
    issue_type          VARCHAR(50)     NOT NULL
                                        CHECK (issue_type IN (
                                            'Wrong Item','Missing Item','Late Delivery',
                                            'Cancelled by Restaurant','Payment Issue',
                                            'Refund Request','App Issue','Quality Issue','Other'
                                        )),
    issue_description   TEXT,
    status              VARCHAR(20)     NOT NULL DEFAULT 'Open'
                                        CHECK (status IN ('Open','In Progress','Resolved','Closed','Escalated')),
    priority            VARCHAR(10)     NOT NULL DEFAULT 'Medium'
                                        CHECK (priority IN ('Low','Medium','High','Critical')),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at         TIMESTAMPTZ,
    resolution_notes    TEXT,
    agent_id            VARCHAR(30),
    sla_breached        BOOLEAN         NOT NULL DEFAULT FALSE
);

CREATE TABLE order_status_history (
    history_id      SERIAL          PRIMARY KEY,
    order_id        INT             NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    status          VARCHAR(30)     NOT NULL,
    changed_at      TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by      VARCHAR(50)     DEFAULT CURRENT_USER,
    notes           TEXT
);
COMMENT ON TABLE order_status_history IS 'Immutable audit trail for every order status change.';

-- Verification
DO $$
DECLARE cnt INT;
BEGIN
    SELECT COUNT(*) INTO cnt FROM information_schema.tables WHERE table_schema = 'public';
    RAISE NOTICE 'Tables created: %', cnt;
END $$;
