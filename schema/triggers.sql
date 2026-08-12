-- =============================================================================
-- FILE:        schema/triggers.sql
-- Description: 7 business-logic triggers for automatic rating updates,
--              audit logging, inventory tracking, and business rule enforcement.
-- =============================================================================

-- =============================================================================
-- TRIGGER 1: Update restaurant rating when a new review is submitted
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_update_restaurant_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE restaurants
    SET rating        = (
            SELECT ROUND(AVG(overall_rating)::numeric, 2)
            FROM reviews
            WHERE restaurant_id = NEW.restaurant_id
              AND overall_rating IS NOT NULL
        ),
        total_ratings = (
            SELECT COUNT(*) FROM reviews WHERE restaurant_id = NEW.restaurant_id
        )
    WHERE restaurant_id = NEW.restaurant_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_restaurant_rating
    AFTER INSERT OR UPDATE ON reviews
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_update_restaurant_rating();

COMMENT ON TRIGGER trg_update_restaurant_rating ON reviews IS
    'Recalculates restaurant.rating after every review submission.';

-- =============================================================================
-- TRIGGER 2: Update delivery partner rating when delivery is rated
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_update_partner_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.delivery_rating IS NOT NULL THEN
        UPDATE delivery_partners
        SET rating = (
            SELECT ROUND(AVG(delivery_rating)::numeric, 2)
            FROM deliveries
            WHERE partner_id = NEW.partner_id
              AND delivery_rating IS NOT NULL
        )
        WHERE partner_id = NEW.partner_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_partner_rating
    AFTER UPDATE ON deliveries
    FOR EACH ROW
    WHEN (NEW.delivery_rating IS DISTINCT FROM OLD.delivery_rating)
    EXECUTE FUNCTION fn_trg_update_partner_rating();

-- =============================================================================
-- TRIGGER 3: Log every order status change to audit trail
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_log_order_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN
        INSERT INTO order_status_history (order_id, status, changed_at)
        VALUES (NEW.order_id, NEW.order_status, CURRENT_TIMESTAMP);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_order_status
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_log_order_status();

COMMENT ON TRIGGER trg_log_order_status ON orders IS
    'Appends to order_status_history on every status change. Immutable audit trail.';

-- Also log on INSERT (initial Placed status)
CREATE OR REPLACE FUNCTION fn_trg_log_order_status_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO order_status_history (order_id, status, changed_at)
    VALUES (NEW.order_id, NEW.order_status, CURRENT_TIMESTAMP);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_order_status_insert
    AFTER INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_log_order_status_insert();

-- =============================================================================
-- TRIGGER 4: Update customer stats when an order is delivered
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_update_customer_stats()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_new_tier VARCHAR(20);
    v_new_total NUMERIC(12,2);
BEGIN
    IF NEW.order_status = 'Delivered' AND OLD.order_status != 'Delivered' THEN
        UPDATE customers
        SET total_orders    = total_orders + 1,
            total_spent     = total_spent + NEW.total_amount,
            last_order_date = NEW.delivered_at
        WHERE customer_id = NEW.customer_id
        RETURNING total_spent INTO v_new_total;

        -- Tier upgrade logic
        v_new_tier := CASE
            WHEN v_new_total >= 10000 THEN 'Platinum'
            WHEN v_new_total >= 5000  THEN 'Gold'
            WHEN v_new_total >= 2000  THEN 'Silver'
            ELSE 'Bronze'
        END;

        UPDATE customers
        SET customer_tier = v_new_tier
        WHERE customer_id = NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_customer_stats
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_update_customer_stats();

-- =============================================================================
-- TRIGGER 5: Update restaurant revenue totals when order is delivered
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_update_restaurant_revenue()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.order_status = 'Delivered' AND OLD.order_status != 'Delivered' THEN
        UPDATE restaurants
        SET total_orders  = total_orders + 1,
            total_revenue = total_revenue + NEW.total_amount
        WHERE restaurant_id = NEW.restaurant_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_restaurant_revenue
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_update_restaurant_revenue();

-- =============================================================================
-- TRIGGER 6: Track promotion usage
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_track_promo_usage()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.promotion_id IS NOT NULL THEN
        UPDATE promotions
        SET current_uses = current_uses + 1
        WHERE promotion_id = NEW.promotion_id;

        -- Auto-deactivate when max uses reached
        UPDATE promotions
        SET is_active = FALSE
        WHERE promotion_id = NEW.promotion_id
          AND max_uses IS NOT NULL
          AND current_uses >= max_uses;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_track_promo_usage
    AFTER INSERT ON orders
    FOR EACH ROW
    WHEN (NEW.promotion_id IS NOT NULL)
    EXECUTE FUNCTION fn_trg_track_promo_usage();

-- =============================================================================
-- TRIGGER 7: Update delivery partner stats on delivery completion
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_trg_update_partner_stats()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.delivery_status = 'Delivered' AND OLD.delivery_status != 'Delivered' THEN
        UPDATE delivery_partners
        SET total_deliveries = total_deliveries + 1,
            total_earnings   = total_earnings + COALESCE(NEW.partner_earnings, 0)
        WHERE partner_id = NEW.partner_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_partner_stats
    AFTER UPDATE ON deliveries
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_update_partner_stats();

COMMENT ON TRIGGER trg_update_partner_stats ON deliveries IS
    'Increments partner total_deliveries and total_earnings on completion.';
