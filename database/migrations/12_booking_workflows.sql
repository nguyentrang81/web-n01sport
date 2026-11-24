USE n01sport_dev;

DELIMITER $$

CREATE FUNCTION has_effective_role(p_user BIGINT, p_role VARCHAR(32), p_facility BIGINT, p_at DATETIME(6))
RETURNS TINYINT READS SQL DATA SQL SECURITY INVOKER
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM user_role_grants g JOIN roles r ON r.id = g.role_id
        JOIN users u ON u.id = g.user_id
        LEFT JOIN coach_profiles cp ON cp.id = g.coach_profile_id
        LEFT JOIN customers cu ON cu.id = cp.customer_id
        LEFT JOIN facility_manager_assignments ma ON ma.id = g.manager_assignment_id
        LEFT JOIN employees me ON me.id = ma.employee_id
        LEFT JOIN facility_staff_assignments sa ON sa.id = g.staff_assignment_id
        LEFT JOIN employees se ON se.id = sa.employee_id
        WHERE g.user_id = p_user AND r.code = p_role AND u.status = 'ACTIVE'
          AND g.granted_at <= p_at AND (g.revoked_at IS NULL OR p_at < g.revoked_at)
          AND (g.facility_id IS NULL OR g.facility_id = p_facility)
          AND CASE r.code
            WHEN 'COACH' THEN cu.user_id = g.user_id AND cp.status = 'APPROVED' AND cp.facility_id = g.facility_id
              AND cp.reviewed_at <= p_at AND (cp.valid_until IS NULL OR cp.valid_until > p_at)
            WHEN 'FACILITY_MANAGER' THEN me.user_id = g.user_id AND me.status = 'ACTIVE'
              AND ma.facility_id = g.facility_id AND ma.starts_at <= p_at AND (ma.ends_at IS NULL OR p_at < ma.ends_at)
            WHEN 'STAFF' THEN se.user_id = g.user_id AND se.status = 'ACTIVE'
              AND sa.facility_id = g.facility_id AND sa.starts_at <= p_at AND (sa.ends_at IS NULL OR p_at < sa.ends_at)
            ELSE TRUE END
    );
END$$

CREATE TRIGGER bookings_capture_initial_state AFTER INSERT ON bookings FOR EACH ROW
BEGIN
    INSERT INTO booking_status_history(booking_id,changed_by,to_status,reason)
    VALUES (NEW.id,NEW.handled_by,NEW.status,NEW.operations_note);
END$$

CREATE TRIGGER bookings_validate_transition BEFORE UPDATE ON bookings FOR EACH ROW
BEGIN
    DECLARE v_now DATETIME(6) DEFAULT UTC_TIMESTAMP(6);
    IF NOT (NEW.code <=> OLD.code AND NEW.customer_id <=> OLD.customer_id AND NEW.court_id <=> OLD.court_id
        AND NEW.series_id <=> OLD.series_id AND NEW.start_at <=> OLD.start_at AND NEW.end_at <=> OLD.end_at
        AND NEW.court_fee <=> OLD.court_fee AND NEW.discount_amount <=> OLD.discount_amount
        AND NEW.amount_due <=> OLD.amount_due AND NEW.created_at <=> OLD.created_at AND NEW.expires_at <=> OLD.expires_at) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Booking quote and schedule are immutable';
    END IF;
    IF NEW.status <> OLD.status AND NOT (
       (NEW.status = 'CONFIRMED' AND OLD.status = 'PENDING_PAYMENT' AND v_now < OLD.expires_at
          AND OLD.amount_due = (SELECT COALESCE(SUM(amount),0) FROM payments WHERE booking_id=OLD.id
                                AND status='SUCCEEDED' AND received_at < OLD.expires_at)
          AND OLD.court_fee = (SELECT COALESCE(SUM(line_amount),-1) FROM booking_price_lines WHERE booking_id=OLD.id)
          AND (OLD.discount_amount=0 OR EXISTS (SELECT 1 FROM promotion_usages WHERE booking_id=OLD.id
               AND status='HELD' AND discount_amount=OLD.discount_amount)))
       OR (NEW.status = 'EXPIRED' AND OLD.status = 'PENDING_PAYMENT' AND v_now >= OLD.expires_at)
       OR (NEW.status = 'CANCELLED' AND OLD.status IN ('PENDING_PAYMENT','CONFIRMED')
          AND v_now <= DATE_SUB(OLD.start_at, INTERVAL 12 HOUR))
       OR (NEW.status = 'CANCELLED' AND OLD.status='CONFIRMED' AND v_now < OLD.start_at
          AND has_effective_role(NEW.handled_by,'OWNER',NULL,v_now)
          AND EXISTS (SELECT 1 FROM refund_requests q JOIN payments p ON p.id=q.payment_id
                     WHERE p.booking_id=OLD.id AND q.status='APPROVED'))
       OR (NEW.status = 'CHECKED_IN' AND OLD.status = 'CONFIRMED'
          AND v_now BETWEEN DATE_SUB(OLD.start_at,INTERVAL 15 MINUTE) AND DATE_ADD(OLD.start_at,INTERVAL 15 MINUTE))
       OR (NEW.status = 'NO_SHOW' AND OLD.status = 'CONFIRMED' AND v_now > DATE_ADD(OLD.start_at,INTERVAL 15 MINUTE))
       OR (NEW.status = 'COMPLETED' AND OLD.status = 'CHECKED_IN' AND v_now >= OLD.end_at)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid booking state transition';
    END IF;
END$$

CREATE TRIGGER bookings_capture_transition AFTER UPDATE ON bookings FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        INSERT INTO booking_status_history(booking_id,changed_by,from_status,to_status,reason)
        VALUES (NEW.id,IF(NEW.status IN ('CONFIRMED','EXPIRED'),NULL,NEW.handled_by),OLD.status,NEW.status,NEW.operations_note);
        IF NEW.status='CONFIRMED' THEN
            UPDATE promotion_usages SET status='USED' WHERE booking_id=NEW.id AND status='HELD';
            UPDATE reward_redemptions r JOIN promotion_usages u ON u.redemption_id=r.id
            SET r.status='USED' WHERE u.booking_id=NEW.id AND u.status='USED';
        ELSEIF NEW.status IN ('EXPIRED','CANCELLED') THEN
            UPDATE promotion_usages SET status='RELEASED' WHERE booking_id=NEW.id AND status='HELD';
        END IF;
    END IF;
END$$

-- Read committed plus the court lock serializes overlapping requests on one court.
-- Public callers supply UTC values. The client must use an authenticated customer profile.
CREATE PROCEDURE hold_booking(
    IN p_code VARCHAR(32), IN p_customer BIGINT, IN p_court BIGINT, IN p_series BIGINT,
    IN p_start DATETIME(6), IN p_end DATETIME(6), IN p_promotion_version BIGINT, IN p_redemption BIGINT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_now DATETIME(6);
    DECLARE v_facility BIGINT;
    DECLARE v_court_facility BIGINT;
    DECLARE v_facility_status VARCHAR(20);
    DECLARE v_court_status VARCHAR(24);
    DECLARE v_customer_user BIGINT;
    DECLARE v_local DATETIME(6);
    DECLARE v_cursor DATETIME(6);
    DECLARE v_day DATE;
    DECLARE v_daytime TIME(6);
    DECLARE v_open_end DATETIME(6);
    DECLARE v_price_end DATETIME(6);
    DECLARE v_segment_end DATETIME(6);
    DECLARE v_rate DECIMAL(14,0);
    DECLARE v_line DECIMAL(14,0);
    DECLARE v_price_id BIGINT;
    DECLARE v_total DECIMAL(14,0) DEFAULT 0;
    DECLARE v_discount DECIMAL(14,0) DEFAULT 0;
    DECLARE v_quote JSON DEFAULT (JSON_ARRAY());
    DECLARE v_promo BIGINT;
    DECLARE v_promo_facility BIGINT;
    DECLARE v_promo_enabled BOOL;
    DECLARE v_promo_type VARCHAR(12);
    DECLARE v_promo_value DECIMAL(14,2);
    DECLARE v_promo_limit INT;
    DECLARE v_voucher BIGINT;
    DECLARE v_old_booking BIGINT;
    DECLARE v_booking BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_started THEN ROLLBACK; END IF;
        RESIGNAL;
    END;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT c.facility_id INTO v_facility FROM courts c WHERE c.id=p_court;
    SELECT status INTO v_facility_status FROM facilities WHERE id=v_facility FOR SHARE;
    SELECT facility_id,status INTO v_court_facility,v_court_status FROM courts WHERE id=p_court FOR UPDATE;
    SET v_now=UTC_TIMESTAMP(6);
    SELECT c.user_id INTO v_customer_user
    FROM customers c JOIN users u ON u.id=c.user_id AND u.status='ACTIVE' WHERE c.id=p_customer;

    IF NULLIF(TRIM(p_code),'') IS NULL OR p_start IS NULL OR p_end IS NULL
       OR p_start <= v_now OR p_start >= p_end OR v_customer_user IS NULL
       OR v_facility_status IS NULL OR v_facility_status <> 'ACTIVE'
       OR v_court_status <> 'ACTIVE' OR NOT (v_court_facility <=> v_facility) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid customer, court, facility or booking period';
    END IF;
    IF p_series IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM booking_series s JOIN coach_profiles cp ON cp.id=s.coach_profile_id
        WHERE s.id=p_series AND cp.customer_id=p_customer
          AND has_effective_role(v_customer_user,'COACH',cp.facility_id,v_now)
          AND DATE(p_start+INTERVAL 7 HOUR) BETWEEN s.first_date AND s.last_date
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Eligible coach series is required';
    END IF;
    IF EXISTS (SELECT 1 FROM bookings b WHERE b.court_id=p_court AND b.start_at<p_end AND p_start<b.end_at
        AND (b.status IN ('CONFIRMED','CHECKED_IN','COMPLETED') OR (b.status='PENDING_PAYMENT' AND b.expires_at>v_now)))
        OR EXISTS (SELECT 1 FROM court_blocks b WHERE b.court_id=p_court AND b.starts_at<p_end
            AND p_start<LEAST(b.ends_at,COALESCE(b.released_at,b.ends_at))
            AND b.starts_at<LEAST(b.ends_at,COALESCE(b.released_at,b.ends_at)))
        OR EXISTS (SELECT 1 FROM facility_suspensions f WHERE f.facility_id=v_facility AND f.starts_at<p_end
            AND (f.ends_at IS NULL OR p_start<f.ends_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Booking conflicts with another booking or unavailable period';
    END IF;

    SET v_cursor=p_start;
    WHILE v_cursor<p_end DO
        SET v_local=v_cursor+INTERVAL 7 HOUR;
        SET v_day=DATE(v_local);
        SET v_daytime=TIME(v_local);
        SELECT MAX(TIMESTAMP(v_day,closes_at)-INTERVAL 7 HOUR) INTO v_open_end FROM court_hours
        WHERE court_id=p_court AND weekday=WEEKDAY(v_day)+1 AND valid_from<=v_day
          AND (valid_to IS NULL OR v_day<valid_to) AND opens_at<=v_daytime AND v_daytime<closes_at;
        SET v_price_id=NULL;
        SELECT id,hourly_rate,TIMESTAMP(v_day,ends_time)-INTERVAL 7 HOUR
          INTO v_price_id,v_rate,v_price_end
        FROM court_prices WHERE court_id=p_court AND weekday=WEEKDAY(v_day)+1 AND valid_from<=v_day
          AND (valid_to IS NULL OR v_day<valid_to) AND starts_time<=v_daytime AND v_daytime<ends_time
          AND approval='APPROVED'
        ORDER BY id LIMIT 1;
        IF v_open_end IS NULL OR v_price_id IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Booking must fit opening hours and approved prices';
        END IF;
        SET v_segment_end=LEAST(p_end,v_open_end,v_price_end);
        IF v_segment_end<=v_cursor THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid opening or price segment';
        END IF;
        SET v_line=ROUND(v_rate*TIMESTAMPDIFF(MICROSECOND,v_cursor,v_segment_end)/3600000000);
        SET v_total=v_total+v_line;
        SET v_quote=JSON_ARRAY_APPEND(v_quote,'$',JSON_OBJECT(
            'price',v_price_id,'rate',v_rate,'start',v_cursor,'end',v_segment_end,'amount',v_line));
        SET v_cursor=v_segment_end;
    END WHILE;

    IF p_promotion_version IS NOT NULL THEN
        SELECT p.id,p.facility_id,p.is_enabled,v.discount_type,v.discount_value,v.usage_limit
          INTO v_promo,v_promo_facility,v_promo_enabled,v_promo_type,v_promo_value,v_promo_limit
        FROM promotion_versions v JOIN promotions p ON p.id=v.promotion_id
        WHERE v.id=p_promotion_version AND v.approval='APPROVED' AND v.starts_at<=v_now AND v_now<v.ends_at
          AND v.min_subtotal<=v_total FOR UPDATE;
        IF v_promo IS NULL OR NOT v_promo_enabled OR (v_promo_facility IS NOT NULL AND v_promo_facility<>v_facility)
          OR (v_promo_limit IS NOT NULL AND v_promo_limit <= (
            SELECT COUNT(*) FROM promotion_usages u JOIN bookings b ON b.id=u.booking_id
            WHERE u.promotion_version_id=p_promotion_version AND
            (u.status='USED' OR (u.status='HELD' AND b.status='PENDING_PAYMENT' AND b.expires_at>v_now))
          )) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Promotion unavailable or no uses left';
        END IF;
        SET v_discount=LEAST(v_total,IF(v_promo_type='FIXED',v_promo_value,ROUND(v_total*v_promo_value/100)));
        IF p_redemption IS NOT NULL THEN
            SELECT r.id INTO v_voucher FROM reward_redemptions r
            JOIN reward_offers o ON o.id=r.reward_offer_id AND o.promotion_id=v_promo
            JOIN loyalty_accounts a ON a.id=r.loyalty_account_id AND a.customer_id=p_customer
            WHERE r.id=p_redemption AND r.status='ISSUED' AND r.expires_at>v_now
              AND EXISTS (SELECT 1 FROM point_transactions t WHERE t.redemption_id=r.id AND t.kind='REDEEM')
            FOR UPDATE OF r;
            IF v_voucher IS NULL THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Voucher is invalid for this customer or promotion';
            END IF;
            SELECT b.id INTO v_old_booking FROM promotion_usages u JOIN bookings b ON b.id=u.booking_id
            WHERE u.redemption_id=p_redemption AND u.status='HELD' AND b.status='PENDING_PAYMENT' AND b.expires_at<=v_now;
            IF v_old_booking IS NOT NULL THEN
                UPDATE bookings SET status='EXPIRED' WHERE id=v_old_booking AND status='PENDING_PAYMENT' AND expires_at<=v_now;
            END IF;
        END IF;
    ELSEIF p_redemption IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Voucher requires a promotion version';
    END IF;

    INSERT INTO bookings(code,customer_id,court_id,series_id,start_at,end_at,court_fee,discount_amount,amount_due,created_at,expires_at)
    VALUES(p_code,p_customer,p_court,p_series,p_start,p_end,v_total,v_discount,v_total-v_discount,v_now,v_now+INTERVAL 15 MINUTE);
    SET v_booking=LAST_INSERT_ID();
    INSERT INTO booking_price_lines(booking_id,court_price_id,start_at,end_at,hourly_rate,line_amount)
    SELECT v_booking,price_id,start_at,end_at,rate,amount FROM JSON_TABLE(v_quote,'$[*]' COLUMNS(
        price_id BIGINT PATH '$.price', start_at DATETIME(6) PATH '$.start', end_at DATETIME(6) PATH '$.end',
        rate DECIMAL(14,0) PATH '$.rate', amount DECIMAL(14,0) PATH '$.amount')) AS segments;
    IF p_promotion_version IS NOT NULL THEN
        INSERT INTO promotion_usages(booking_id,promotion_version_id,redemption_id,discount_amount)
        VALUES(v_booking,p_promotion_version,p_redemption,v_discount);
    END IF;
    IF v_total=v_discount THEN
        UPDATE bookings SET status='CONFIRMED' WHERE id=v_booking;
    END IF;
    COMMIT;
    SELECT id,code,amount_due,status,expires_at FROM bookings WHERE id=v_booking;
END$$

CREATE PROCEDURE create_payment_request(
    IN p_booking BIGINT, IN p_key VARCHAR(100), IN p_amount DECIMAL(14,0)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_status VARCHAR(24);
    DECLARE v_expiry DATETIME(6);
    DECLARE v_due DECIMAL(14,0);
    DECLARE v_payment BIGINT;
    DECLARE v_original_booking BIGINT;
    DECLARE v_original_amount DECIMAL(14,0);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT status,expires_at,amount_due INTO v_status,v_expiry,v_due FROM bookings WHERE id=p_booking FOR UPDATE;
    SELECT id,booking_id,amount INTO v_payment,v_original_booking,v_original_amount FROM payments WHERE idempotency_key=p_key;
    IF v_payment IS NOT NULL THEN
        IF p_booking<>v_original_booking OR NOT (p_amount <=> v_original_amount) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment key already used for a different request';
        END IF;
    ELSE
        IF v_status IS NULL OR v_status<>'PENDING_PAYMENT' OR v_expiry<=UTC_TIMESTAMP(6)
            OR NULLIF(TRIM(p_key),'') IS NULL OR p_amount IS NULL OR p_amount<=0
            OR p_amount>v_due-(SELECT COALESCE(SUM(amount),0) FROM payments WHERE booking_id=p_booking AND status='SUCCEEDED') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment requires a live hold and outstanding balance';
        END IF;
        INSERT INTO payments(booking_id,idempotency_key,amount) VALUES (p_booking,p_key,p_amount);
        SET v_payment=LAST_INSERT_ID();
    END IF;
    COMMIT;
    SELECT id,booking_id,amount,status,provider_ref,qr_payload FROM payments WHERE id=v_payment;
END$$


-- Store the reference and QR after the application's provider API has created them.
CREATE PROCEDURE attach_payment_gateway(
    IN p_payment BIGINT, IN p_provider_ref VARCHAR(120), IN p_qr TEXT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_booking BIGINT;
    DECLARE v_booking_status VARCHAR(24);
    DECLARE v_status VARCHAR(24);
    DECLARE v_ref VARCHAR(120);
    DECLARE v_expires DATETIME(6);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT booking_id INTO v_booking FROM payments WHERE id=p_payment;
    SELECT status,expires_at INTO v_booking_status,v_expires FROM bookings WHERE id=v_booking FOR UPDATE;
    SELECT status,provider_ref INTO v_status,v_ref FROM payments WHERE id=p_payment FOR UPDATE;
    IF v_booking_status IS NULL OR v_status IS NULL OR NULLIF(TRIM(p_provider_ref),'') IS NULL
        OR NULLIF(TRIM(p_qr),'') IS NULL OR (v_ref IS NOT NULL AND CAST(v_ref AS BINARY)<>CAST(p_provider_ref AS BINARY))
        OR (v_status='PENDING' AND (v_booking_status<>'PENDING_PAYMENT' OR v_expires<=UTC_TIMESTAMP(6)))
        OR (v_status<>'PENDING' AND v_ref IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Gateway details do not match a live payment';
    END IF;
    IF v_status='PENDING' THEN
        UPDATE payments SET provider_ref=p_provider_ref,qr_payload=p_qr WHERE id=p_payment;
    END IF;
    COMMIT;
    SELECT id,status,provider_ref,qr_payload FROM payments WHERE id=p_payment;
END$$

-- Invoke only from the server after authenticating the provider's callback.
-- Provider reference and event keys must include the provider namespace.
CREATE PROCEDURE record_payment_callback(
    IN p_payment BIGINT, IN p_provider_ref VARCHAR(120), IN p_event_key VARCHAR(150),
    IN p_amount DECIMAL(14,0), IN p_success BOOL
)
SQL SECURITY DEFINER
callback: BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_booking BIGINT;
    DECLARE v_status VARCHAR(24);
    DECLARE v_payment_status VARCHAR(24);
    DECLARE v_expected DECIMAL(14,0);
    DECLARE v_due DECIMAL(14,0);
    DECLARE v_paid DECIMAL(14,0);
    DECLARE v_event_payment BIGINT;
    DECLARE v_event_amount DECIMAL(14,0);
    DECLARE v_reference VARCHAR(120);
    DECLARE v_expires DATETIME(6);
    DECLARE v_now DATETIME(6);
    DECLARE v_result VARCHAR(24);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount<0 OR p_success IS NULL OR p_success NOT IN (0,1)
       OR NULLIF(TRIM(p_provider_ref),'') IS NULL OR NULLIF(TRIM(p_event_key),'') IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid callback input';
    END IF;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT booking_id INTO v_booking FROM payments WHERE id=p_payment;
    SELECT status,expires_at,amount_due INTO v_status,v_expires,v_due FROM bookings WHERE id=v_booking FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment or booking does not exist'; END IF;
    SELECT status,provider_ref,amount INTO v_payment_status,v_reference,v_expected FROM payments WHERE id=p_payment FOR UPDATE;
    SET v_now=UTC_TIMESTAMP(6);
    SELECT payment_id,reported_amount INTO v_event_payment,v_event_amount FROM payment_events WHERE event_key=p_event_key;
    IF v_event_payment IS NOT NULL THEN
        IF v_event_payment<>p_payment OR v_event_amount<>p_amount THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Callback event key already used for another payment or amount';
        END IF;
        COMMIT;
        SELECT 'DUPLICATE' AS outcome;
        LEAVE callback;
    END IF;
    IF v_expected<>p_amount OR (v_reference IS NOT NULL AND BINARY v_reference<>BINARY p_provider_ref) THEN
        SET v_result='MISMATCH';
    ELSEIF v_payment_status IN ('SUCCEEDED','LATE_SUCCESS') THEN
        SET v_result='ALREADY_CAPTURED';
    ELSEIF NOT p_success THEN
        UPDATE payments SET status='FAILED',provider_ref=p_provider_ref WHERE id=p_payment;
        SET v_result='FAILED';
    ELSE
        IF v_status='PENDING_PAYMENT' AND v_now>=v_expires THEN
            UPDATE bookings SET status='EXPIRED' WHERE id=v_booking;
            SET v_status='EXPIRED';
        END IF;
        SELECT COALESCE(SUM(amount),0) INTO v_paid FROM payments WHERE booking_id=v_booking AND status='SUCCEEDED';
        IF v_status<>'PENDING_PAYMENT' OR v_paid+p_amount>v_due THEN
            UPDATE payments SET status='LATE_SUCCESS',provider_ref=p_provider_ref,received_at=v_now WHERE id=p_payment;
            SET v_result='RECONCILE';
        ELSE
            UPDATE payments SET status='SUCCEEDED',provider_ref=p_provider_ref,received_at=v_now WHERE id=p_payment;
            SET v_result='SUCCEEDED';
            IF v_paid+p_amount=v_due THEN UPDATE bookings SET status='CONFIRMED' WHERE id=v_booking; END IF;
        END IF;
    END IF;
    INSERT INTO payment_events(payment_id,event_key,reported_amount,received_at,outcome)
    VALUES(p_payment,p_event_key,p_amount,v_now,v_result);
    COMMIT;
    SELECT v_result AS outcome;
END$$

CREATE PROCEDURE expire_bookings()
SQL SECURITY DEFINER
BEGIN
    UPDATE bookings SET status='EXPIRED' WHERE status='PENDING_PAYMENT' AND expires_at<=UTC_TIMESTAMP(6)
    ORDER BY expires_at,id LIMIT 1000;
    SELECT ROW_COUNT() AS expired_count;
END$$

CREATE PROCEDURE move_booking(IN p_booking BIGINT, IN p_actor BIGINT, IN p_status VARCHAR(24), IN p_reason TEXT)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_facility BIGINT;
    DECLARE v_status VARCHAR(24);
    DECLARE v_customer_user BIGINT;
    DECLARE v_now DATETIME(6);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT b.status,c.facility_id,u.user_id INTO v_status,v_facility,v_customer_user
    FROM bookings b JOIN courts c ON c.id=b.court_id JOIN customers u ON u.id=b.customer_id
    WHERE b.id=p_booking FOR UPDATE OF b;
    SET v_now=UTC_TIMESTAMP(6);
    IF v_status IS NULL OR p_actor IS NULL OR NOT EXISTS(SELECT 1 FROM users WHERE id=p_actor AND status='ACTIVE')
      OR NOT (
        (p_status='CANCELLED' AND (p_actor=v_customer_user OR has_effective_role(p_actor,'OWNER',NULL,v_now)))
        OR (p_status IN ('CHECKED_IN','NO_SHOW','COMPLETED') AND (
          has_effective_role(p_actor,'FACILITY_MANAGER',v_facility,v_now)
          OR (has_effective_role(p_actor,'STAFF',v_facility,v_now) AND EXISTS (
              SELECT 1 FROM employees e JOIN facility_staff_assignments a ON a.employee_id=e.id
              WHERE e.user_id=p_actor AND a.facility_id=v_facility AND a.position_code='RECEPTIONIST'
                AND a.starts_at<=v_now AND (a.ends_at IS NULL OR a.ends_at>v_now)
          ))
        ))
      ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Actor or booking change is not permitted';
    END IF;
    UPDATE bookings SET status=p_status,handled_by=p_actor,operations_note=p_reason WHERE id=p_booking;
    COMMIT;
    SELECT id,status FROM bookings WHERE id=p_booking;
END$$

DELIMITER ;
