-- =============================================================================
-- FILE:        procedures/delivery_management.sql
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_assign_delivery_partner(
    p_order_id  INT,
    OUT p_partner_id INT,
    OUT p_partner_name VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_zone_id   INT;
    v_exp_time  INT;
BEGIN
    SELECT zone_id INTO v_zone_id FROM orders WHERE order_id = p_order_id;

    -- Find best available partner in zone (fewest active deliveries)
    SELECT dp.partner_id, dp.partner_name
    INTO   p_partner_id, p_partner_name
    FROM   delivery_partners dp
    WHERE  dp.zone_id = v_zone_id
      AND  dp.is_active = TRUE
      AND  dp.current_status = 'Available'
      AND  dp.bg_verification = TRUE
    ORDER BY dp.total_deliveries DESC, dp.rating DESC
    LIMIT 1;

    IF p_partner_id IS NULL THEN
        -- Fallback: any active partner in the city
        SELECT dp.partner_id, dp.partner_name
        INTO   p_partner_id, p_partner_name
        FROM   delivery_partners dp
        JOIN   zones z ON dp.zone_id = z.zone_id
        JOIN   orders o ON o.order_id = p_order_id
        JOIN   zones oz ON o.zone_id = oz.zone_id
        WHERE  dp.is_active = TRUE AND dp.current_status = 'Available'
          AND  z.city_id = oz.city_id
        LIMIT 1;
    END IF;

    IF p_partner_id IS NULL THEN
        RAISE EXCEPTION 'No available delivery partners for order %', p_order_id
              USING ERRCODE = 'P0010';
    END IF;

    SELECT avg_delivery_time_mins INTO v_exp_time
    FROM zones WHERE zone_id = v_zone_id;

    INSERT INTO deliveries(order_id, partner_id, assigned_at,
                           expected_delivery_time, expected_time_mins,
                           delivery_status)
    VALUES (p_order_id, p_partner_id, CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP + (v_exp_time || ' minutes')::INTERVAL,
            v_exp_time, 'Assigned');

    UPDATE orders SET order_status = 'Confirmed', confirmed_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    UPDATE delivery_partners SET current_status = 'On Delivery'
    WHERE partner_id = p_partner_id;

    RAISE NOTICE 'Order % assigned to partner % (%)', p_order_id, p_partner_id, p_partner_name;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_complete_delivery(
    p_order_id      INT,
    p_actual_mins   INT,
    p_distance_km   NUMERIC DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_partner_id    INT;
    v_fee           NUMERIC(6,2);
BEGIN
    SELECT partner_id, delivery_fee INTO v_partner_id, v_fee
    FROM deliveries WHERE order_id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No delivery record for order %', p_order_id;
    END IF;

    UPDATE deliveries
    SET delivery_status = 'Delivered',
        delivered_at    = CURRENT_TIMESTAMP,
        actual_time_mins = p_actual_mins,
        distance_km     = COALESCE(p_distance_km, distance_km),
        partner_earnings = ROUND(COALESCE(v_fee, 39) * 0.7 + COALESCE(p_distance_km, 3.0) * 2, 2)
    WHERE order_id = p_order_id;

    UPDATE orders
    SET order_status = 'Delivered',
        delivered_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    UPDATE delivery_partners
    SET current_status = 'Available'
    WHERE partner_id = v_partner_id;

    RAISE NOTICE 'Order % delivered in % mins by partner %',
        p_order_id, p_actual_mins, v_partner_id;
END;
$$;
