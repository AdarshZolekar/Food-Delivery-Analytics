-- =============================================================================
-- FILE:        schema/constraints.sql
-- =============================================================================

-- Unique constraints
ALTER TABLE customers      ADD CONSTRAINT uq_customers_email   UNIQUE (email);
ALTER TABLE customers      ADD CONSTRAINT uq_customers_phone   UNIQUE (phone);
ALTER TABLE delivery_partners ADD CONSTRAINT uq_partner_phone  UNIQUE (phone);
ALTER TABLE restaurants    ADD CONSTRAINT uq_restaurant_email  UNIQUE (email);

-- Business rule: max discount cannot exceed order subtotal
ALTER TABLE orders ADD CONSTRAINT chk_discount_lte_subtotal
    CHECK (discount_amount <= subtotal_amount);

-- Business rule: total = subtotal - discount + delivery_fee + taxes
-- (enforced in procedures, not as DB constraint, due to floating point)

-- Promo validity
ALTER TABLE promotions ADD CONSTRAINT chk_promo_discount_positive
    CHECK (discount_value > 0);

-- Delivery time must be positive
ALTER TABLE deliveries ADD CONSTRAINT chk_delivery_time_positive
    CHECK (actual_time_mins IS NULL OR actual_time_mins > 0);

-- Review: only one review per order per customer (already UNIQUE)
-- Verified: customer must have a delivered order to review
