-- =============================================================================
-- FILE:        procedures/order_management.sql
-- =============================================================================

-- =============================================================================
-- PROCEDURE: Place a new order
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_place_order(
    p_customer_id   INT,
    p_restaurant_id INT,
    p_address_id    INT,
    p_items         JSONB,          -- [{"item_id":1,"quantity":2}, ...]
    p_promo_code    VARCHAR DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT 'UPI',
    p_channel       VARCHAR DEFAULT 'App',
    OUT p_order_id  INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item          JSONB;
    v_item_price    NUMERIC(8,2);
    v_item_name     VARCHAR(200);
    v_subtotal      NUMERIC(10,2) := 0;
    v_discount      NUMERIC(8,2)  := 0;
    v_delivery_fee  NUMERIC(6,2)  := 39.00;
    v_taxes         NUMERIC(8,2);
    v_total         NUMERIC(10,2);
    v_commission_rate NUMERIC(5,2);
    v_commission    NUMERIC(8,2);
    v_promo_id      INT;
    v_zone_id       INT;
    v_qty           INT;
BEGIN
    -- Validate customer
    IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = p_customer_id AND is_active) THEN
        RAISE EXCEPTION 'Customer % not found or inactive', p_customer_id USING ERRCODE = 'P0001';
    END IF;
    -- Validate restaurant
    IF NOT EXISTS (SELECT 1 FROM restaurants WHERE restaurant_id = p_restaurant_id AND is_active) THEN
        RAISE EXCEPTION 'Restaurant % not found or inactive', p_restaurant_id USING ERRCODE = 'P0002';
    END IF;

    -- Get zone from restaurant
    SELECT zone_id INTO v_zone_id FROM restaurants WHERE restaurant_id = p_restaurant_id;

    -- Calculate subtotal from items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_qty := (v_item->>'quantity')::INT;
        SELECT price, item_name INTO v_item_price, v_item_name
        FROM menu_items
        WHERE item_id = (v_item->>'item_id')::INT AND is_available = TRUE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Item % not available', v_item->>'item_id' USING ERRCODE = 'P0003';
        END IF;
        v_subtotal := v_subtotal + (v_item_price * v_qty);
    END LOOP;

    -- Apply promotion
    IF p_promo_code IS NOT NULL THEN
        SELECT promotion_id, discount_value, promo_type, max_discount, min_order_amount
        INTO v_promo_id
        FROM promotions
        WHERE promo_code = p_promo_code
          AND is_active = TRUE
          AND CURRENT_DATE BETWEEN start_date AND end_date
          AND (max_uses IS NULL OR current_uses < max_uses)
          AND v_subtotal >= min_order_amount;

        IF FOUND THEN
            DECLARE v_p promotions%ROWTYPE;
            BEGIN
                SELECT * INTO v_p FROM promotions WHERE promotion_id = v_promo_id;
                v_discount := CASE v_p.promo_type
                    WHEN 'FLAT'         THEN LEAST(v_p.discount_value, v_subtotal)
                    WHEN 'PERCENT'      THEN LEAST(v_subtotal * v_p.discount_value / 100,
                                                   COALESCE(v_p.max_discount, 999999))
                    WHEN 'FREE_DELIVERY' THEN v_delivery_fee
                    ELSE 0
                END;
                IF v_p.promo_type = 'FREE_DELIVERY' THEN
                    v_delivery_fee := 0;
                    v_discount := 0;
                END IF;
            END;
        END IF;
    END IF;

    -- Compute totals
    v_taxes      := ROUND((v_subtotal - v_discount) * 0.05, 2);
    v_total      := ROUND(v_subtotal - v_discount + v_delivery_fee + v_taxes, 2);

    SELECT commission_rate INTO v_commission_rate FROM restaurants WHERE restaurant_id = p_restaurant_id;
    v_commission := ROUND(v_total * v_commission_rate / 100, 2);

    -- Create order
    INSERT INTO orders(customer_id, restaurant_id, address_id, zone_id, promotion_id,
                       order_channel, subtotal_amount, discount_amount, delivery_fee,
                       taxes, total_amount, platform_commission, payment_method)
    VALUES (p_customer_id, p_restaurant_id, p_address_id, v_zone_id, v_promo_id,
            p_channel, v_subtotal, v_discount, v_delivery_fee,
            v_taxes, v_total, v_commission, p_payment_method)
    RETURNING order_id INTO p_order_id;

    -- Insert items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        SELECT price INTO v_item_price FROM menu_items WHERE item_id = (v_item->>'item_id')::INT;
        INSERT INTO order_items(order_id, item_id, quantity, unit_price)
        VALUES (p_order_id, (v_item->>'item_id')::INT, (v_item->>'quantity')::INT, v_item_price);
    END LOOP;

    -- Payment record
    INSERT INTO payments(order_id, amount, payment_method, payment_status, transaction_id)
    VALUES (p_order_id, v_total, p_payment_method, 'Completed',
            'TXN' || LPAD(p_order_id::TEXT, 10, '0'));

    RAISE NOTICE 'Order % placed. Total: ₹%', p_order_id, v_total;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_place_order failed: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END;
$$;

-- =============================================================================
-- PROCEDURE: Cancel an order
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_cancel_order(
    p_order_id  INT,
    p_reason    TEXT DEFAULT 'Customer requested cancellation'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR(30);
    v_amount NUMERIC(10,2);
BEGIN
    SELECT order_status, total_amount INTO v_status, v_amount
    FROM orders WHERE order_id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', p_order_id;
    END IF;
    IF v_status IN ('Delivered', 'Cancelled') THEN
        RAISE EXCEPTION 'Cannot cancel order in status: %', v_status;
    END IF;

    UPDATE orders
    SET order_status = 'Cancelled', cancelled_at = CURRENT_TIMESTAMP,
        cancellation_reason = p_reason
    WHERE order_id = p_order_id;

    UPDATE payments
    SET payment_status = 'Refunded', refund_amount = v_amount,
        refund_timestamp = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id AND payment_status = 'Completed';

    RAISE NOTICE 'Order % cancelled. Refund: ₹%', p_order_id, v_amount;
END;
$$;
