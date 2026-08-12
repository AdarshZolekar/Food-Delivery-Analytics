-- =============================================================================
-- FILE:        procedures/customer_operations.sql
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_process_refund(
    p_order_id      INT,
    p_refund_amount NUMERIC DEFAULT NULL,
    p_reason        TEXT DEFAULT 'Customer complaint'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_paid_amount   NUMERIC(10,2);
    v_refund        NUMERIC(10,2);
BEGIN
    SELECT amount INTO v_paid_amount FROM payments WHERE order_id = p_order_id
    AND payment_status = 'Completed' LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No completed payment for order %', p_order_id;
    END IF;

    v_refund := COALESCE(p_refund_amount, v_paid_amount);

    IF v_refund > v_paid_amount THEN
        RAISE EXCEPTION 'Refund amount (%) exceeds paid amount (%)', v_refund, v_paid_amount;
    END IF;

    UPDATE payments
    SET payment_status   = CASE WHEN v_refund = v_paid_amount THEN 'Refunded'
                                ELSE 'Partially Refunded' END,
        refund_amount    = v_refund,
        refund_timestamp = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id AND payment_status = 'Completed';

    UPDATE orders SET is_refunded = TRUE, refund_amount = v_refund
    WHERE order_id = p_order_id;

    RAISE NOTICE 'Refund of ₹% processed for order %', v_refund, p_order_id;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_update_restaurant_rating(p_restaurant_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_avg NUMERIC(3,2);
    v_cnt INT;
BEGIN
    SELECT ROUND(AVG(overall_rating)::numeric,2), COUNT(*)
    INTO v_avg, v_cnt
    FROM reviews WHERE restaurant_id = p_restaurant_id AND overall_rating IS NOT NULL;

    UPDATE restaurants
    SET rating = COALESCE(v_avg, 0), total_ratings = COALESCE(v_cnt, 0)
    WHERE restaurant_id = p_restaurant_id;

    RAISE NOTICE 'Restaurant % rating updated to % (%  reviews)', p_restaurant_id, v_avg, v_cnt;
END;
$$;
