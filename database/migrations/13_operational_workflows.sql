USE n01sport_dev;

DELIMITER $$

CREATE TRIGGER users_revoke_sessions AFTER UPDATE ON users FOR EACH ROW
BEGIN
    IF (NEW.status<>OLD.status AND NEW.status IN ('LOCKED','DISABLED'))
        OR NOT (NEW.password_hash <=> OLD.password_hash) THEN
        UPDATE auth_sessions SET revoked_at=GREATEST(created_at,UTC_TIMESTAMP(6))
        WHERE user_id=NEW.id AND revoked_at IS NULL;
    END IF;
END$$

CREATE PROCEDURE grant_application_role(
    IN p_actor BIGINT, IN p_user BIGINT, IN p_role VARCHAR(32), IN p_facility BIGINT,
    IN p_coach_profile BIGINT, IN p_manager_assignment BIGINT, IN p_staff_assignment BIGINT, IN p_reason TEXT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_role BIGINT;
    DECLARE v_grant BIGINT;
    DECLARE v_now DATETIME(6);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT id INTO v_role FROM roles WHERE code=p_role FOR UPDATE;
    SET v_now=UTC_TIMESTAMP(6);
    IF v_role IS NULL OR NOT EXISTS (SELECT 1 FROM users WHERE id=p_user) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown recipient or application role';
    END IF;
    IF p_actor IS NULL AND p_role='SYSTEM_ADMIN' THEN
        IF EXISTS (SELECT 1 FROM user_role_grants WHERE role_id=v_role)
           OR NOT EXISTS (SELECT 1 FROM users WHERE id=p_user AND status='ACTIVE') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='The initial admin requires an active user and is bootstrapped only once';
        END IF;
    ELSEIF NOT (p_actor IS NULL AND p_role='CUSTOMER')
       AND NOT has_effective_role(p_actor,'SYSTEM_ADMIN',NULL,v_now) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active system admin must grant roles';
    END IF;
    IF p_role='COACH' THEN
        IF p_manager_assignment IS NOT NULL OR p_staff_assignment IS NOT NULL OR NOT EXISTS (
            SELECT 1 FROM coach_profiles cp JOIN customers cu ON cu.id=cp.customer_id
            WHERE cp.id=p_coach_profile AND cu.user_id=p_user AND cp.facility_id=p_facility
              AND cp.status='APPROVED' AND cp.reviewed_at<=v_now AND (cp.valid_until IS NULL OR cp.valid_until>v_now)
        ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved coach profile and matching facility are required'; END IF;
    ELSEIF p_role='FACILITY_MANAGER' THEN
        IF p_coach_profile IS NOT NULL OR p_staff_assignment IS NOT NULL OR NOT EXISTS (
            SELECT 1 FROM facility_manager_assignments a JOIN employees e ON e.id=a.employee_id
            WHERE a.id=p_manager_assignment AND e.user_id=p_user AND e.status='ACTIVE' AND a.facility_id=p_facility
              AND a.starts_at<=v_now AND (a.ends_at IS NULL OR a.ends_at>v_now)
        ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active matching manager appointment is required'; END IF;
    ELSEIF p_role='STAFF' THEN
        IF p_coach_profile IS NOT NULL OR p_manager_assignment IS NOT NULL OR NOT EXISTS (
            SELECT 1 FROM facility_staff_assignments a JOIN employees e ON e.id=a.employee_id
            WHERE a.id=p_staff_assignment AND e.user_id=p_user AND e.status='ACTIVE' AND a.facility_id=p_facility
              AND a.starts_at<=v_now AND (a.ends_at IS NULL OR a.ends_at>v_now)
        ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active matching staff assignment is required'; END IF;
    ELSEIF p_facility IS NOT NULL OR p_coach_profile IS NOT NULL OR p_manager_assignment IS NOT NULL OR p_staff_assignment IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Global roles cannot carry facility or assignment references';
    END IF;
    INSERT INTO user_role_grants(user_id,role_id,facility_id,coach_profile_id,manager_assignment_id,staff_assignment_id,granted_by,granted_at,reason)
    VALUES(p_user,v_role,p_facility,p_coach_profile,p_manager_assignment,p_staff_assignment,p_actor,v_now,p_reason);
    SET v_grant=LAST_INSERT_ID();
    COMMIT;
    SELECT v_grant AS grant_id;
END$$

CREATE PROCEDURE revoke_application_role(IN p_actor BIGINT, IN p_grant BIGINT)
SQL SECURITY DEFINER
BEGIN
    IF NOT has_effective_role(p_actor,'SYSTEM_ADMIN',NULL,UTC_TIMESTAMP(6)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active system admin must revoke roles';
    END IF;
    UPDATE user_role_grants SET revoked_by=p_actor,revoked_at=UTC_TIMESTAMP(6)
    WHERE id=p_grant AND revoked_at IS NULL;
    SELECT ROW_COUNT() AS revoked;
END$$

CREATE TRIGGER point_transactions_apply AFTER INSERT ON point_transactions FOR EACH ROW
BEGIN
    DECLARE v_balance INT;
    UPDATE loyalty_accounts SET balance=balance+NEW.points_delta
    WHERE id=NEW.loyalty_account_id AND (NEW.kind<>'REDEEM' OR balance>=-NEW.points_delta);
    IF ROW_COUNT()=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient points or unknown account'; END IF;
    SELECT balance INTO v_balance FROM loyalty_accounts WHERE id=NEW.loyalty_account_id;
    UPDATE loyalty_accounts SET tier_id=COALESCE((SELECT id FROM loyalty_tiers WHERE min_points<=GREATEST(v_balance,0)
        ORDER BY min_points DESC,id LIMIT 1),tier_id)
    WHERE id=NEW.loyalty_account_id;
END$$

CREATE TRIGGER bookings_award_points AFTER UPDATE ON bookings FOR EACH ROW
FOLLOWS bookings_capture_transition
BEGIN
    DECLARE v_rule BIGINT;
    DECLARE v_vnd INT;
    DECLARE v_points INT;
    DECLARE v_account BIGINT;
    IF NEW.status='COMPLETED' AND OLD.status<>'COMPLETED' AND NOT EXISTS (
        SELECT 1 FROM payments p JOIN refund_requests q ON q.payment_id=p.id JOIN refunds r ON r.request_id=q.id
        WHERE p.booking_id=NEW.id AND r.status='SUCCEEDED'
    ) THEN
        SELECT id,vnd_per_point INTO v_rule,v_vnd FROM loyalty_rules
        WHERE starts_at<=UTC_TIMESTAMP(6) AND (ends_at IS NULL OR ends_at>UTC_TIMESTAMP(6))
        ORDER BY starts_at DESC,id DESC LIMIT 1;
        SET v_points=FLOOR(NEW.amount_due/v_vnd);
        IF v_points>0 THEN
            INSERT INTO loyalty_accounts(customer_id,tier_id)
            SELECT NEW.customer_id,id FROM loyalty_tiers WHERE code='STANDARD'
            ON DUPLICATE KEY UPDATE loyalty_accounts.id=loyalty_accounts.id;
            SELECT id INTO v_account FROM loyalty_accounts WHERE customer_id=NEW.customer_id;
            INSERT INTO point_transactions(loyalty_account_id,booking_id,rule_id,dedup_key,kind,points_delta)
            VALUES(v_account,NEW.id,v_rule,CONCAT('booking-earn:',NEW.id),'EARN',v_points);
        END IF;
    END IF;
END$$

CREATE PROCEDURE redeem_loyalty_reward(IN p_account BIGINT, IN p_offer BIGINT, IN p_code VARCHAR(60), IN p_expires DATETIME(6))
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_cost INT;
    DECLARE v_balance INT;
    DECLARE v_reward BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT points_cost INTO v_cost FROM reward_offers WHERE id=p_offer AND is_active FOR SHARE;
    SELECT balance INTO v_balance FROM loyalty_accounts WHERE id=p_account FOR UPDATE;
    IF v_cost IS NULL OR v_balance IS NULL OR v_balance<v_cost OR p_expires<=UTC_TIMESTAMP(6)
       OR NULLIF(TRIM(p_code),'') IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Reward, expiration or loyalty balance is invalid';
    END IF;
    INSERT INTO reward_redemptions(loyalty_account_id,reward_offer_id,voucher_code,expires_at)
    VALUES(p_account,p_offer,p_code,p_expires);
    SET v_reward=LAST_INSERT_ID();
    INSERT INTO point_transactions(loyalty_account_id,redemption_id,dedup_key,kind,points_delta)
    VALUES(p_account,v_reward,CONCAT('reward-redeem:',v_reward),'REDEEM',-v_cost);
    COMMIT;
    SELECT v_reward AS redemption_id;
END$$

CREATE PROCEDURE submit_refund_request(
    IN p_payment BIGINT, IN p_actor BIGINT, IN p_amount DECIMAL(14,0), IN p_reason TEXT, IN p_evidence TEXT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_facility BIGINT;
    DECLARE v_capture DECIMAL(14,0);
    SELECT c.facility_id,p.amount INTO v_facility,v_capture
    FROM payments p JOIN bookings b ON b.id=p.booking_id JOIN courts c ON c.id=b.court_id
    WHERE p.id=p_payment AND p.status IN ('SUCCEEDED','LATE_SUCCESS');
    IF v_facility IS NULL OR NOT has_effective_role(p_actor,'FACILITY_MANAGER',v_facility,UTC_TIMESTAMP(6))
       OR p_amount IS NULL OR p_amount<=0 OR p_amount>v_capture THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Refund request requires a valid captured payment and its facility manager';
    END IF;
    INSERT INTO refund_requests(payment_id,requested_by,amount,reason,evidence_ref)
    VALUES(p_payment,p_actor,p_amount,p_reason,p_evidence);
    SELECT LAST_INSERT_ID() AS request_id;
END$$

CREATE PROCEDURE decide_refund_request(IN p_request BIGINT, IN p_actor BIGINT, IN p_approve BOOL)
SQL SECURITY DEFINER
BEGIN
    IF p_approve IS NULL OR p_approve NOT IN (0,1)
       OR NOT has_effective_role(p_actor,'OWNER',NULL,UTC_TIMESTAMP(6)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only the owner can decide a pending refund request';
    END IF;
    UPDATE refund_requests SET status=IF(p_approve,'APPROVED','REJECTED'),decided_by=p_actor,decided_at=UTC_TIMESTAMP(6)
    WHERE id=p_request AND status='PENDING';
    IF ROW_COUNT()<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Pending refund request not found'; END IF;
END$$

CREATE PROCEDURE create_refund_attempt(IN p_request BIGINT, IN p_key VARCHAR(100), IN p_amount DECIMAL(14,0))
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_payment BIGINT;
    DECLARE v_capture DECIMAL(14,0);
    DECLARE v_allowed DECIMAL(14,0);
    DECLARE v_used DECIMAL(14,0);
    DECLARE v_used_request DECIMAL(14,0);
    DECLARE v_attempt BIGINT;
    DECLARE v_existing_request BIGINT;
    DECLARE v_existing_amount DECIMAL(14,0);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT payment_id INTO v_payment FROM refund_requests WHERE id=p_request AND status='APPROVED';
    SELECT amount INTO v_capture FROM payments WHERE id=v_payment AND status IN ('SUCCEEDED','LATE_SUCCESS') FOR UPDATE;
    SELECT amount INTO v_allowed FROM refund_requests WHERE id=p_request AND status='APPROVED';
    SELECT id,request_id,amount INTO v_attempt,v_existing_request,v_existing_amount FROM refunds WHERE attempt_key=p_key;
    IF v_attempt IS NOT NULL THEN
        IF v_existing_request<>p_request OR NOT (v_existing_amount <=> p_amount) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Refund attempt key was already used';
        END IF;
    ELSE
        SELECT COALESCE(SUM(r.amount),0),COALESCE(SUM(IF(r.request_id=p_request,r.amount,0)),0)
        INTO v_used,v_used_request FROM refunds r JOIN refund_requests q ON q.id=r.request_id
        WHERE q.payment_id=v_payment AND r.status IN ('PENDING','SUCCEEDED');
        IF v_capture IS NULL OR v_allowed IS NULL OR NULLIF(TRIM(p_key),'') IS NULL
           OR p_amount IS NULL OR p_amount<=0 OR v_used+p_amount>v_capture OR v_used_request+p_amount>v_allowed THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Refund exceeds approved or captured amount';
        END IF;
        INSERT INTO refunds(request_id,attempt_key,amount) VALUES(p_request,p_key,p_amount);
        SET v_attempt=LAST_INSERT_ID();
    END IF;
    COMMIT;
    SELECT v_attempt AS refund_id;
END$$

CREATE PROCEDURE settle_refund_attempt(
    IN p_attempt BIGINT, IN p_reference VARCHAR(120), IN p_amount DECIMAL(14,0), IN p_success BOOL
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_booking BIGINT;
    DECLARE v_locked BIGINT;
    DECLARE v_payment BIGINT;
    DECLARE v_amount DECIMAL(14,0);
    DECLARE v_status VARCHAR(20);
    DECLARE v_original_ref VARCHAR(120);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT p.id,p.booking_id INTO v_payment,v_booking FROM refunds r JOIN refund_requests q ON q.id=r.request_id
    JOIN payments p ON p.id=q.payment_id WHERE r.id=p_attempt AND q.status='APPROVED';
    SELECT id INTO v_locked FROM bookings WHERE id=v_booking FOR UPDATE;
    SELECT id INTO v_locked FROM payments WHERE id=v_payment FOR UPDATE;
    SELECT amount,status,provider_ref INTO v_amount,v_status,v_original_ref FROM refunds WHERE id=p_attempt FOR UPDATE;
    IF v_payment IS NULL OR NOT (v_amount <=> p_amount) OR NULLIF(TRIM(p_reference),'') IS NULL
       OR p_success IS NULL OR p_success NOT IN (0,1)
       OR (v_original_ref IS NOT NULL AND BINARY p_reference<>BINARY v_original_ref) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Refund callback does not match an approved attempt';
    END IF;
    IF v_status='PENDING' THEN
        UPDATE refunds SET status=IF(p_success,'SUCCEEDED','FAILED'),provider_ref=p_reference,
            settled_at=IF(p_success,UTC_TIMESTAMP(6),NULL) WHERE id=p_attempt;
        IF p_success AND NOT EXISTS (SELECT 1 FROM point_transactions WHERE booking_id=v_booking AND kind='REVERSAL') THEN
            INSERT INTO point_transactions(loyalty_account_id,booking_id,rule_id,dedup_key,kind,points_delta)
            SELECT loyalty_account_id,booking_id,rule_id,CONCAT('booking-reversal:',booking_id),'REVERSAL',-points_delta
            FROM point_transactions WHERE booking_id=v_booking AND kind='EARN';
        END IF;
    ELSEIF (v_status='SUCCEEDED')<>p_success THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Refund callback conflicts with a settled attempt';
    END IF;
    COMMIT;
    SELECT id,status FROM refunds WHERE id=p_attempt;
END$$

CREATE PROCEDURE settle_sale_payment(
    IN p_order BIGINT, IN p_actor BIGINT, IN p_key VARCHAR(100), IN p_method VARCHAR(24), IN p_amount DECIMAL(14,0)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_started BOOL DEFAULT FALSE;
    DECLARE v_facility BIGINT;
    DECLARE v_state VARCHAR(20);
    DECLARE v_order_total DECIMAL(14,0);
    DECLARE v_sum DECIMAL(14,0);
    DECLARE v_count INT;
    DECLARE v_payment BIGINT;
    DECLARE v_previous_order BIGINT;
    DECLARE v_previous_total DECIMAL(14,0);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_started THEN ROLLBACK; END IF; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SET v_started=TRUE;
    SELECT facility_id,status,total_amount INTO v_facility,v_state,v_order_total FROM sales_orders WHERE id=p_order FOR UPDATE;
    IF NOT (has_effective_role(p_actor,'STAFF',v_facility,UTC_TIMESTAMP(6)) OR
            has_effective_role(p_actor,'FACILITY_MANAGER',v_facility,UTC_TIMESTAMP(6)) OR
            has_effective_role(p_actor,'OWNER',NULL,UTC_TIMESTAMP(6))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='The operator does not have sales access at this facility';
    END IF;
    SELECT id,order_id,amount INTO v_payment,v_previous_order,v_previous_total FROM sales_payments
    WHERE payment_key=p_key AND status='SUCCEEDED';
    IF v_payment IS NOT NULL THEN
        IF v_previous_order<>p_order OR NOT (v_previous_total <=> p_amount) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sale payment key is already in use';
        END IF;
    ELSE
        SELECT COUNT(*),SUM(l.quantity*l.unit_price) INTO v_count,v_sum FROM sales_order_lines l
        JOIN facility_inventory i ON i.id=l.inventory_id AND i.facility_id=v_facility WHERE l.order_id=p_order;
        IF v_state IS NULL OR v_state<>'PENDING' OR v_count=0 OR v_count<>(SELECT COUNT(*) FROM sales_order_lines WHERE order_id=p_order)
           OR NOT (p_amount <=> v_sum) OR v_sum<>v_order_total OR NULLIF(TRIM(p_key),'') IS NULL
           OR NULLIF(TRIM(p_method),'') IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment must match an open order and its line totals';
        END IF;
        UPDATE facility_inventory i JOIN sales_order_lines l ON l.inventory_id=i.id AND l.order_id=p_order
        SET i.on_hand=i.on_hand-l.quantity WHERE i.facility_id=v_facility AND i.on_hand>=l.quantity;
        IF ROW_COUNT()<>v_count THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient facility stock'; END IF;
        INSERT INTO sales_payments(order_id,recorded_by,payment_key,method,amount,status,paid_at)
        VALUES(p_order,p_actor,p_key,p_method,p_amount,'SUCCEEDED',UTC_TIMESTAMP(6));
        SET v_payment=LAST_INSERT_ID();
        UPDATE sales_orders SET status='PAID' WHERE id=p_order;
    END IF;
    COMMIT;
    SELECT id,status,amount FROM sales_payments WHERE id=v_payment;
END$$

CREATE TRIGGER court_hours_insert_guard BEFORE INSERT ON court_hours FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM courts WHERE id=NEW.court_id FOR UPDATE;
    IF NEW.opens_at<'00:00:00' OR NEW.closes_at>'24:00:00' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Opening hours must be within the local day';
    END IF;
    SELECT x.id INTO v_conflict FROM court_hours x WHERE x.court_id=NEW.court_id AND x.weekday=NEW.weekday
      AND (x.valid_to IS NULL OR NEW.valid_from<x.valid_to)
      AND (NEW.valid_to IS NULL OR x.valid_from<NEW.valid_to) AND x.opens_at<NEW.closes_at AND NEW.opens_at<x.closes_at
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Opening periods overlap';
    END IF;
END$$
CREATE TRIGGER court_hours_update_guard BEFORE UPDATE ON court_hours FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    IF NOT (NEW.court_id <=> OLD.court_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM courts WHERE id=NEW.court_id FOR UPDATE;
    IF NEW.opens_at<'00:00:00' OR NEW.closes_at>'24:00:00' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Opening hours must be within the local day';
    END IF;
    SELECT x.id INTO v_conflict FROM court_hours x WHERE x.court_id=NEW.court_id AND x.weekday=NEW.weekday
      AND (x.valid_to IS NULL OR NEW.valid_from<x.valid_to)
      AND (NEW.valid_to IS NULL OR x.valid_from<NEW.valid_to) AND x.opens_at<NEW.closes_at AND NEW.opens_at<x.closes_at
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Opening periods overlap';
    END IF;
END$$
CREATE TRIGGER court_prices_insert_guard BEFORE INSERT ON court_prices FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM courts WHERE id=NEW.court_id FOR UPDATE;
    IF NEW.starts_time<'00:00:00' OR NEW.ends_time>'24:00:00'
      OR (NEW.id<>0 AND NEW.supersedes_id=NEW.id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid price interval or parent price';
    END IF;
    IF NEW.approval='APPROVED' AND NOT has_effective_role(NEW.decided_by,'OWNER',NULL,UTC_TIMESTAMP(6)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active owner must approve prices';
    END IF;
    SELECT x.id INTO v_conflict FROM court_prices x WHERE x.court_id=NEW.court_id AND x.weekday=NEW.weekday
      AND (x.valid_to IS NULL OR NEW.valid_from<x.valid_to)
      AND (NEW.valid_to IS NULL OR x.valid_from<NEW.valid_to)
      AND NEW.approval='APPROVED' AND x.approval='APPROVED'
      AND x.starts_time<NEW.ends_time AND NEW.starts_time<x.ends_time
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved court prices overlap';
    END IF;
END$$
CREATE TRIGGER court_prices_update_guard BEFORE UPDATE ON court_prices FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    IF NOT (NEW.court_id <=> OLD.court_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM courts WHERE id=NEW.court_id FOR UPDATE;
    IF NEW.starts_time<'00:00:00' OR NEW.ends_time>'24:00:00'
      OR (NEW.id<>0 AND NEW.supersedes_id=NEW.id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid price interval or parent price';
    END IF;
    IF NEW.approval='APPROVED' AND NOT has_effective_role(NEW.decided_by,'OWNER',NULL,UTC_TIMESTAMP(6)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active owner must approve prices';
    END IF;
    SELECT x.id INTO v_conflict FROM court_prices x WHERE x.court_id=NEW.court_id AND x.weekday=NEW.weekday
      AND (x.valid_to IS NULL OR NEW.valid_from<x.valid_to)
      AND (NEW.valid_to IS NULL OR x.valid_from<NEW.valid_to)
      AND NEW.approval='APPROVED' AND x.approval='APPROVED'
      AND x.starts_time<NEW.ends_time AND NEW.starts_time<x.ends_time
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved court prices overlap';
    END IF;
END$$
CREATE TRIGGER facility_manager_assignments_insert_guard BEFORE INSERT ON facility_manager_assignments FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM facilities WHERE id=NEW.facility_id FOR UPDATE;
    SELECT x.id INTO v_conflict FROM facility_manager_assignments x WHERE x.facility_id=NEW.facility_id
      AND (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Manager appointments overlap';
    END IF;
END$$
CREATE TRIGGER facility_manager_assignments_update_guard BEFORE UPDATE ON facility_manager_assignments FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    IF NOT (NEW.facility_id <=> OLD.facility_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM facilities WHERE id=NEW.facility_id FOR UPDATE;
    SELECT x.id INTO v_conflict FROM facility_manager_assignments x WHERE x.facility_id=NEW.facility_id
      AND (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Manager appointments overlap';
    END IF;
END$$
CREATE TRIGGER facility_staff_assignments_insert_guard BEFORE INSERT ON facility_staff_assignments FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM facilities WHERE id=NEW.facility_id FOR UPDATE;
    SELECT x.id INTO v_conflict FROM facility_staff_assignments x WHERE x.facility_id=NEW.facility_id
      AND x.employee_id=NEW.employee_id AND x.position_code=NEW.position_code
      AND (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Staff assignments overlap';
    END IF;
END$$
CREATE TRIGGER facility_staff_assignments_update_guard BEFORE UPDATE ON facility_staff_assignments FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    IF NOT (NEW.facility_id <=> OLD.facility_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM facilities WHERE id=NEW.facility_id FOR UPDATE;
    SELECT x.id INTO v_conflict FROM facility_staff_assignments x WHERE x.facility_id=NEW.facility_id
      AND x.employee_id=NEW.employee_id AND x.position_code=NEW.position_code
      AND (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Staff assignments overlap';
    END IF;
END$$
CREATE TRIGGER promotion_versions_insert_guard BEFORE INSERT ON promotion_versions FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM promotions WHERE id=NEW.promotion_id FOR UPDATE;
    IF NEW.approval='APPROVED' AND NOT has_effective_role(NEW.decided_by,'OWNER',NULL,UTC_TIMESTAMP(6)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active owner must approve promotion versions';
    END IF;
    SELECT x.id INTO v_conflict FROM promotion_versions x WHERE x.promotion_id=NEW.promotion_id
      AND NEW.approval='APPROVED' AND x.approval='APPROVED'
      AND x.starts_at<NEW.ends_at AND NEW.starts_at<x.ends_at
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved promotion versions overlap';
    END IF;
END$$
CREATE TRIGGER promotion_versions_update_guard BEFORE UPDATE ON promotion_versions FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    IF NOT (NEW.promotion_id <=> OLD.promotion_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM promotions WHERE id=NEW.promotion_id FOR UPDATE;
    IF NEW.approval='APPROVED' AND NOT has_effective_role(NEW.decided_by,'OWNER',NULL,UTC_TIMESTAMP(6)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active owner must approve promotion versions';
    END IF;
    SELECT x.id INTO v_conflict FROM promotion_versions x WHERE x.promotion_id=NEW.promotion_id
      AND NEW.approval='APPROVED' AND x.approval='APPROVED'
      AND x.starts_at<NEW.ends_at AND NEW.starts_at<x.ends_at
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved promotion versions overlap';
    END IF;
END$$
CREATE TRIGGER loyalty_rules_insert_guard BEFORE INSERT ON loyalty_rules FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM roles WHERE code='OWNER' FOR UPDATE;
    SELECT x.id INTO v_conflict FROM loyalty_rules x WHERE (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Loyalty rules overlap';
    END IF;
END$$
CREATE TRIGGER loyalty_rules_update_guard BEFORE UPDATE ON loyalty_rules FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM roles WHERE code='OWNER' FOR UPDATE;
    SELECT x.id INTO v_conflict FROM loyalty_rules x WHERE (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Loyalty rules overlap';
    END IF;
END$$
CREATE TRIGGER court_blocks_insert_guard BEFORE INSERT ON court_blocks FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    DECLARE v_end DATETIME(6);
    SELECT id INTO v_lock FROM courts WHERE id=NEW.court_id FOR UPDATE;
    SET v_end=LEAST(NEW.ends_at,COALESCE(NEW.released_at,NEW.ends_at));
    IF NEW.starts_at<v_end AND EXISTS (
        SELECT 1 FROM bookings b WHERE b.court_id=NEW.court_id AND b.end_at>UTC_TIMESTAMP(6)
          AND b.start_at<v_end AND NEW.starts_at<b.end_at
          AND (b.status IN ('CONFIRMED','CHECKED_IN')
            OR (b.status='PENDING_PAYMENT' AND b.expires_at>UTC_TIMESTAMP(6)))
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolve affected bookings before blocking the court'; END IF;
    SELECT x.id INTO v_conflict FROM court_blocks x WHERE x.court_id=NEW.court_id AND x.starts_at < v_end
      AND NEW.starts_at < LEAST(x.ends_at,COALESCE(x.released_at,x.ends_at))
      AND x.starts_at < LEAST(x.ends_at,COALESCE(x.released_at,x.ends_at)) AND NEW.starts_at<v_end
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Court blocks overlap';
    END IF;
END$$
CREATE TRIGGER court_blocks_update_guard BEFORE UPDATE ON court_blocks FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    DECLARE v_end DATETIME(6);
    IF NOT (NEW.court_id <=> OLD.court_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM courts WHERE id=NEW.court_id FOR UPDATE;
    SET v_end=LEAST(NEW.ends_at,COALESCE(NEW.released_at,NEW.ends_at));
    IF NEW.starts_at<v_end AND EXISTS (
        SELECT 1 FROM bookings b WHERE b.court_id=NEW.court_id AND b.end_at>UTC_TIMESTAMP(6)
          AND b.start_at<v_end AND NEW.starts_at<b.end_at
          AND (b.status IN ('CONFIRMED','CHECKED_IN')
            OR (b.status='PENDING_PAYMENT' AND b.expires_at>UTC_TIMESTAMP(6)))
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolve affected bookings before blocking the court'; END IF;
    SELECT x.id INTO v_conflict FROM court_blocks x WHERE x.court_id=NEW.court_id AND x.starts_at < v_end
      AND NEW.starts_at < LEAST(x.ends_at,COALESCE(x.released_at,x.ends_at))
      AND x.starts_at < LEAST(x.ends_at,COALESCE(x.released_at,x.ends_at)) AND NEW.starts_at<v_end
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Court blocks overlap';
    END IF;
END$$
CREATE TRIGGER facility_suspensions_insert_guard BEFORE INSERT ON facility_suspensions FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    SELECT id INTO v_lock FROM facilities WHERE id=NEW.facility_id FOR UPDATE;
    IF EXISTS (
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE c.facility_id=NEW.facility_id
          AND b.end_at>UTC_TIMESTAMP(6) AND (NEW.ends_at IS NULL OR b.start_at<NEW.ends_at) AND NEW.starts_at<b.end_at
          AND (b.status IN ('CONFIRMED','CHECKED_IN')
            OR (b.status='PENDING_PAYMENT' AND b.expires_at>UTC_TIMESTAMP(6)))
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolve affected bookings before suspending a facility'; END IF;
    SELECT x.id INTO v_conflict FROM facility_suspensions x WHERE x.facility_id=NEW.facility_id
      AND (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Facility suspensions overlap';
    END IF;
END$$
CREATE TRIGGER facility_suspensions_update_guard BEFORE UPDATE ON facility_suspensions FOR EACH ROW
BEGIN
    DECLARE v_lock BIGINT;
    DECLARE v_conflict BIGINT;
    IF NOT (NEW.facility_id <=> OLD.facility_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Parent scope is immutable';
    END IF;
    SELECT id INTO v_lock FROM facilities WHERE id=NEW.facility_id FOR UPDATE;
    IF EXISTS (
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE c.facility_id=NEW.facility_id
          AND b.end_at>UTC_TIMESTAMP(6) AND (NEW.ends_at IS NULL OR b.start_at<NEW.ends_at) AND NEW.starts_at<b.end_at
          AND (b.status IN ('CONFIRMED','CHECKED_IN')
            OR (b.status='PENDING_PAYMENT' AND b.expires_at>UTC_TIMESTAMP(6)))
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolve affected bookings before suspending a facility'; END IF;
    SELECT x.id INTO v_conflict FROM facility_suspensions x WHERE x.facility_id=NEW.facility_id
      AND (x.ends_at IS NULL OR NEW.starts_at<x.ends_at) AND (NEW.ends_at IS NULL OR x.starts_at<NEW.ends_at)
    AND x.id<>OLD.id
    LIMIT 1 FOR SHARE;
    IF v_conflict IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Facility suspensions overlap';
    END IF;
END$$
CREATE TRIGGER court_prices_version_guard BEFORE UPDATE ON court_prices FOR EACH ROW
BEGIN
    IF OLD.approval='APPROVED' AND (NEW.approval<>'APPROVED' OR NOT (NEW.court_id<=>OLD.court_id AND NEW.weekday<=>OLD.weekday AND NEW.starts_time<=>OLD.starts_time AND NEW.ends_time<=>OLD.ends_time AND NEW.hourly_rate<=>OLD.hourly_rate AND NEW.valid_from<=>OLD.valid_from)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved terms are fixed; close this version and create a new one';
    END IF;
END$$
CREATE TRIGGER promotion_versions_version_guard BEFORE UPDATE ON promotion_versions FOR EACH ROW
BEGIN
    IF OLD.approval='APPROVED' AND (NEW.approval<>'APPROVED' OR NOT (NEW.promotion_id<=>OLD.promotion_id AND NEW.discount_type<=>OLD.discount_type AND NEW.discount_value<=>OLD.discount_value AND NEW.starts_at<=>OLD.starts_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Approved terms are fixed; close this version and create a new one';
    END IF;
END$$
CREATE TRIGGER facilities_update_guard BEFORE UPDATE ON facilities FOR EACH ROW
BEGIN
    IF NEW.status<>'ACTIVE' AND NEW.status<>OLD.status AND EXISTS(
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE c.facility_id=NEW.id AND b.end_at>UTC_TIMESTAMP(6)
         AND (b.status IN ('CONFIRMED','CHECKED_IN') OR (b.status='PENDING_PAYMENT' AND b.expires_at>UTC_TIMESTAMP(6)))
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolve affected bookings before changing status'; END IF;
END$$
CREATE TRIGGER facilities_insert_audit AFTER INSERT ON facilities FOR EACH ROW
BEGIN
    INSERT INTO audit_logs(facility_id,action,entity_type,entity_key,details)
    VALUES(NEW.id,'AVAILABILITY_STATUS','facilities',CAST(NEW.id AS CHAR),JSON_OBJECT('status',NEW.status));
END$$
CREATE TRIGGER facilities_update_audit AFTER UPDATE ON facilities FOR EACH ROW
BEGIN
    IF NEW.status<>OLD.status THEN
    INSERT INTO audit_logs(facility_id,action,entity_type,entity_key,details)
    VALUES(NEW.id,'AVAILABILITY_STATUS','facilities',CAST(NEW.id AS CHAR),JSON_OBJECT('status',NEW.status));
    END IF;
END$$
CREATE TRIGGER courts_update_guard BEFORE UPDATE ON courts FOR EACH ROW
BEGIN
    IF NOT (NEW.facility_id<=>OLD.facility_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Court facility is immutable';
    END IF;
    IF NEW.status<>'ACTIVE' AND NEW.status<>OLD.status AND EXISTS(
        SELECT 1 FROM bookings b  WHERE b.court_id=NEW.id AND b.end_at>UTC_TIMESTAMP(6)
         AND (b.status IN ('CONFIRMED','CHECKED_IN') OR (b.status='PENDING_PAYMENT' AND b.expires_at>UTC_TIMESTAMP(6)))
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Resolve affected bookings before changing status'; END IF;
END$$
CREATE TRIGGER courts_insert_audit AFTER INSERT ON courts FOR EACH ROW
BEGIN
    INSERT INTO audit_logs(facility_id,action,entity_type,entity_key,details)
    VALUES(NEW.facility_id,'AVAILABILITY_STATUS','courts',CAST(NEW.id AS CHAR),JSON_OBJECT('status',NEW.status));
END$$
CREATE TRIGGER courts_update_audit AFTER UPDATE ON courts FOR EACH ROW
BEGIN
    IF NEW.status<>OLD.status THEN
    INSERT INTO audit_logs(facility_id,action,entity_type,entity_key,details)
    VALUES(NEW.facility_id,'AVAILABILITY_STATUS','courts',CAST(NEW.id AS CHAR),JSON_OBJECT('status',NEW.status));
    END IF;
END$$
CREATE TRIGGER sales_order_lines_insert_guard BEFORE INSERT ON sales_order_lines FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_facility BIGINT;
    SELECT facility_id,status INTO v_facility,v_status FROM sales_orders WHERE id=NEW.order_id FOR UPDATE;
    IF v_status IS NULL OR v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only pending sale items can change';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM facility_inventory WHERE id=NEW.inventory_id AND facility_id=v_facility) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sale inventory belongs to another facility';
    END IF;
END$$
CREATE TRIGGER sales_order_lines_update_guard BEFORE UPDATE ON sales_order_lines FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_facility BIGINT;
    IF NEW.order_id<>OLD.order_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sale line cannot move between orders';
    END IF;
    SELECT facility_id,status INTO v_facility,v_status FROM sales_orders WHERE id=NEW.order_id FOR UPDATE;
    IF v_status IS NULL OR v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only pending sale items can change';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM facility_inventory WHERE id=NEW.inventory_id AND facility_id=v_facility) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sale inventory belongs to another facility';
    END IF;
END$$
CREATE TRIGGER sales_order_lines_delete_guard BEFORE DELETE ON sales_order_lines FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_facility BIGINT;
    SELECT facility_id,status INTO v_facility,v_status FROM sales_orders WHERE id=OLD.order_id FOR UPDATE;
    IF v_status IS NULL OR v_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only pending sale items can change';
    END IF;
END$$
CREATE TRIGGER sales_orders_insert_guard BEFORE INSERT ON sales_orders FOR EACH ROW
BEGIN
    IF NEW.status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='A new sale must be pending';
    END IF;
    IF NEW.booking_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE b.id=NEW.booking_id
          AND c.facility_id=NEW.facility_id AND (NEW.customer_id IS NULL OR b.customer_id=NEW.customer_id)
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Order and booking scope differ'; END IF;
END$$
CREATE TRIGGER sales_orders_update_guard BEFORE UPDATE ON sales_orders FOR EACH ROW
BEGIN
    IF NOT (NEW.facility_id<=>OLD.facility_id AND NEW.customer_id<=>OLD.customer_id AND NEW.booking_id<=>OLD.booking_id)
       OR (OLD.status<>'PENDING' AND NOT (NEW.total_amount<=>OLD.total_amount AND NEW.status<=>OLD.status)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Closed sale and its scope are immutable';
    END IF;
    IF NEW.status='PAID' AND NOT EXISTS (
        SELECT 1 FROM sales_payments WHERE order_id=NEW.id AND amount=NEW.total_amount AND status='SUCCEEDED'
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Paid sale requires its captured payment'; END IF;
    IF NEW.booking_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE b.id=NEW.booking_id
          AND c.facility_id=NEW.facility_id AND (NEW.customer_id IS NULL OR b.customer_id=NEW.customer_id)
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Order and booking scope differ'; END IF;
END$$
CREATE TRIGGER rental_orders_insert_guard BEFORE INSERT ON rental_orders FOR EACH ROW
BEGIN
    IF NEW.booking_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE b.id=NEW.booking_id
          AND c.facility_id=NEW.facility_id AND (NEW.customer_id IS NULL OR b.customer_id=NEW.customer_id)
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Order and booking scope differ'; END IF;
END$$
CREATE TRIGGER rental_orders_update_guard BEFORE UPDATE ON rental_orders FOR EACH ROW
BEGIN
    IF NOT (NEW.facility_id<=>OLD.facility_id AND NEW.customer_id<=>OLD.customer_id AND NEW.booking_id<=>OLD.booking_id
                AND NEW.starts_at<=>OLD.starts_at AND NEW.ends_at<=>OLD.ends_at)
       AND EXISTS (SELECT 1 FROM rental_order_lines WHERE rental_id=OLD.id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rental scope and schedule are fixed after adding assets';
    END IF;
    IF NEW.booking_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM bookings b JOIN courts c ON c.id=b.court_id WHERE b.id=NEW.booking_id
          AND c.facility_id=NEW.facility_id AND (NEW.customer_id IS NULL OR b.customer_id=NEW.customer_id)
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Order and booking scope differ'; END IF;
END$$
CREATE TRIGGER rental_order_lines_insert_guard BEFORE INSERT ON rental_order_lines FOR EACH ROW
BEGIN
    DECLARE v_order_facility BIGINT;
    DECLARE v_asset_facility BIGINT;
    DECLARE v_asset_status VARCHAR(24);
    DECLARE v_order_status VARCHAR(24);
    DECLARE v_start DATETIME(6);
    DECLARE v_end DATETIME(6);
    DECLARE v_conflict BIGINT;

    SELECT facility_id,status,starts_at,ends_at INTO v_order_facility,v_order_status,v_start,v_end
    FROM rental_orders WHERE id=NEW.rental_id FOR UPDATE;
    SELECT facility_id,condition_status INTO v_asset_facility,v_asset_status
    FROM equipment_items WHERE id=NEW.equipment_id FOR UPDATE;
    IF v_order_facility IS NULL OR v_asset_facility IS NULL OR v_order_facility<>v_asset_facility
       OR v_order_status NOT IN ('PENDING','HANDED_OVER') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rental asset must belong to an open order facility';
    END IF;
    IF NEW.returned_at IS NULL THEN
        SELECT l.id INTO v_conflict FROM rental_order_lines l JOIN rental_orders o ON o.id=l.rental_id
        WHERE l.equipment_id=NEW.equipment_id 
          AND l.returned_at IS NULL AND o.status IN ('PENDING','HANDED_OVER')
          AND o.starts_at<v_end AND v_start<o.ends_at LIMIT 1 FOR SHARE OF l;
        IF v_conflict IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Equipment reservation overlaps'; END IF;
    END IF;
    IF NEW.handed_at IS NOT NULL  THEN
        IF v_asset_status<>'AVAILABLE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Equipment is not available for handover'; END IF;
        UPDATE equipment_items SET condition_status='IN_USE' WHERE id=NEW.equipment_id;
    END IF;
    IF NEW.returned_at IS NOT NULL  THEN
        UPDATE equipment_items SET condition_status=CASE NEW.return_condition WHEN 'LOST' THEN 'LOST'
              WHEN 'DAMAGED' THEN 'DAMAGED' ELSE 'AVAILABLE' END WHERE id=NEW.equipment_id;
    END IF;
END$$
CREATE TRIGGER rental_order_lines_update_guard BEFORE UPDATE ON rental_order_lines FOR EACH ROW
BEGIN
    DECLARE v_order_facility BIGINT;
    DECLARE v_asset_facility BIGINT;
    DECLARE v_asset_status VARCHAR(24);
    DECLARE v_order_status VARCHAR(24);
    DECLARE v_start DATETIME(6);
    DECLARE v_end DATETIME(6);
    DECLARE v_conflict BIGINT;
    IF NEW.rental_id<>OLD.rental_id OR NEW.equipment_id<>OLD.equipment_id
        OR (OLD.handed_at IS NOT NULL AND NOT (NEW.handed_at<=>OLD.handed_at))
        OR (OLD.returned_at IS NOT NULL AND NOT (NEW.returned_at<=>OLD.returned_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rental assignment and recorded handover are fixed';
    END IF;
    SELECT facility_id,status,starts_at,ends_at INTO v_order_facility,v_order_status,v_start,v_end
    FROM rental_orders WHERE id=NEW.rental_id FOR UPDATE;
    SELECT facility_id,condition_status INTO v_asset_facility,v_asset_status
    FROM equipment_items WHERE id=NEW.equipment_id FOR UPDATE;
    IF v_order_facility IS NULL OR v_asset_facility IS NULL OR v_order_facility<>v_asset_facility
       OR v_order_status NOT IN ('PENDING','HANDED_OVER') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rental asset must belong to an open order facility';
    END IF;
    IF NEW.returned_at IS NULL THEN
        SELECT l.id INTO v_conflict FROM rental_order_lines l JOIN rental_orders o ON o.id=l.rental_id
        WHERE l.equipment_id=NEW.equipment_id AND l.id<>OLD.id
          AND l.returned_at IS NULL AND o.status IN ('PENDING','HANDED_OVER')
          AND o.starts_at<v_end AND v_start<o.ends_at LIMIT 1 FOR SHARE OF l;
        IF v_conflict IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Equipment reservation overlaps'; END IF;
    END IF;
    IF NEW.handed_at IS NOT NULL AND OLD.handed_at IS NULL THEN
        IF v_asset_status<>'AVAILABLE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Equipment is not available for handover'; END IF;
        UPDATE equipment_items SET condition_status='IN_USE' WHERE id=NEW.equipment_id;
    END IF;
    IF NEW.returned_at IS NOT NULL AND OLD.returned_at IS NULL THEN
        UPDATE equipment_items SET condition_status=CASE NEW.return_condition WHEN 'LOST' THEN 'LOST'
              WHEN 'DAMAGED' THEN 'DAMAGED' ELSE 'AVAILABLE' END WHERE id=NEW.equipment_id;
    END IF;
END$$
CREATE TRIGGER staff_shifts_insert_guard BEFORE INSERT ON staff_shifts FOR EACH ROW
BEGIN
    IF NOT EXISTS(SELECT 1 FROM facility_staff_assignments a WHERE a.id=NEW.staff_assignment_id
            AND a.starts_at<=NEW.starts_at AND (a.ends_at IS NULL OR NEW.ends_at<=a.ends_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER staff_shifts_update_guard BEFORE UPDATE ON staff_shifts FOR EACH ROW
BEGIN
    IF NOT EXISTS(SELECT 1 FROM facility_staff_assignments a WHERE a.id=NEW.staff_assignment_id
            AND a.starts_at<=NEW.starts_at AND (a.ends_at IS NULL OR NEW.ends_at<=a.ends_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER technical_tickets_insert_guard BEFORE INSERT ON technical_tickets FOR EACH ROW
BEGIN
    IF (NEW.court_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM courts WHERE id=NEW.court_id AND facility_id=NEW.facility_id))
        OR (NEW.equipment_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM equipment_items WHERE id=NEW.equipment_id AND facility_id=NEW.facility_id)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER technical_tickets_update_guard BEFORE UPDATE ON technical_tickets FOR EACH ROW
BEGIN
    IF (NEW.court_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM courts WHERE id=NEW.court_id AND facility_id=NEW.facility_id))
        OR (NEW.equipment_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM equipment_items WHERE id=NEW.equipment_id AND facility_id=NEW.facility_id)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER technical_assignments_insert_guard BEFORE INSERT ON technical_assignments FOR EACH ROW
BEGIN
    IF NOT EXISTS(SELECT 1 FROM technical_tickets t JOIN facility_staff_assignments a
          ON a.facility_id=t.facility_id WHERE t.id=NEW.ticket_id AND a.id=NEW.staff_assignment_id AND a.position_code='TECHNICAL'
          AND a.starts_at<=NEW.assigned_at AND (a.ends_at IS NULL OR a.ends_at>NEW.assigned_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER technical_assignments_update_guard BEFORE UPDATE ON technical_assignments FOR EACH ROW
BEGIN
    IF NOT EXISTS(SELECT 1 FROM technical_tickets t JOIN facility_staff_assignments a
          ON a.facility_id=t.facility_id WHERE t.id=NEW.ticket_id AND a.id=NEW.staff_assignment_id AND a.position_code='TECHNICAL'
          AND a.starts_at<=NEW.assigned_at AND (a.ends_at IS NULL OR a.ends_at>NEW.assigned_at)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER cleaning_tasks_insert_guard BEFORE INSERT ON cleaning_tasks FOR EACH ROW
BEGIN
    IF NOT EXISTS(SELECT 1 FROM staff_shifts sh JOIN facility_staff_assignments a ON a.id=sh.staff_assignment_id
          WHERE sh.id=NEW.shift_id AND a.position_code='CLEANING'
            AND sh.starts_at<=NEW.scheduled_at AND NEW.scheduled_at<sh.ends_at
            AND (NEW.court_id IS NULL OR EXISTS (SELECT 1 FROM courts WHERE id=NEW.court_id AND facility_id=a.facility_id))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER cleaning_tasks_update_guard BEFORE UPDATE ON cleaning_tasks FOR EACH ROW
BEGIN
    IF NOT EXISTS(SELECT 1 FROM staff_shifts sh JOIN facility_staff_assignments a ON a.id=sh.staff_assignment_id
          WHERE sh.id=NEW.shift_id AND a.position_code='CLEANING'
            AND sh.starts_at<=NEW.scheduled_at AND NEW.scheduled_at<sh.ends_at
            AND (NEW.court_id IS NULL OR EXISTS (SELECT 1 FROM courts WHERE id=NEW.court_id AND facility_id=a.facility_id))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER notifications_insert_guard BEFORE INSERT ON notifications FOR EACH ROW
BEGIN
    IF NEW.payment_id IS NOT NULL AND NEW.booking_id IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM payments WHERE id=NEW.payment_id AND booking_id=NEW.booking_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER notifications_update_guard BEFORE UPDATE ON notifications FOR EACH ROW
BEGIN
    IF NEW.payment_id IS NOT NULL AND NEW.booking_id IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM payments WHERE id=NEW.payment_id AND booking_id=NEW.booking_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER backup_jobs_insert_guard BEFORE INSERT ON backup_jobs FOR EACH ROW
BEGIN
    IF NEW.kind='RESTORE' AND NOT EXISTS(SELECT 1 FROM backup_jobs b WHERE b.id=NEW.source_backup_id
          AND (NEW.id=0 OR NEW.id<>b.id) AND b.kind='BACKUP' AND b.status='SUCCEEDED' AND b.integrity_ref IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$
CREATE TRIGGER backup_jobs_update_guard BEFORE UPDATE ON backup_jobs FOR EACH ROW
BEGIN
    IF NEW.kind='RESTORE' AND NOT EXISTS(SELECT 1 FROM backup_jobs b WHERE b.id=NEW.source_backup_id
          AND (NEW.id=0 OR NEW.id<>b.id) AND b.kind='BACKUP' AND b.status='SUCCEEDED' AND b.integrity_ref IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid referenced scope or operational evidence';
    END IF;
END$$

DELIMITER ;
