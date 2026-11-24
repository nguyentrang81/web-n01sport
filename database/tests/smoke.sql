-- Chạy bằng tests/run.ps1. Chọn đúng database n01sport_test_* trước khi chạy thủ công.
DELIMITER $$
CREATE PROCEDURE n01sport_smoke_assert(IN p_ok BOOL, IN p_message VARCHAR(128))
BEGIN
    IF NOT COALESCE(p_ok,FALSE) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=p_message; END IF;
END$$
DELIMITER ;

CALL n01sport_smoke_assert(DATABASE() LIKE 'n01sport\_test\_%', 'This test requires a separate n01sport_test_* database');
SELECT COUNT(*) INTO @n FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE';
CALL n01sport_smoke_assert(@n=66,'Expected 66 tables');
SELECT COUNT(*) INTO @n FROM information_schema.views WHERE table_schema=DATABASE();
CALL n01sport_smoke_assert(@n=3,'Expected 3 views');
SELECT COUNT(*) INTO @n FROM information_schema.referential_constraints WHERE constraint_schema=DATABASE();
CALL n01sport_smoke_assert(@n=133,'Expected 133 foreign keys');
SELECT COUNT(*) INTO @n FROM roles;
CALL n01sport_smoke_assert(@n=6,'Expected 6 default application roles');

INSERT INTO users (id,email,full_name,password_hash,status) VALUES
 (1001,'test-admin@example.invalid','Test admin','test-not-a-credential','ACTIVE'),
 (1002,'test-owner@example.invalid','Test owner','test-not-a-credential','ACTIVE'),
 (1003,'test-manager@example.invalid','Test manager','test-not-a-credential','ACTIVE'),
 (1004,'test-customer@example.invalid','Test customer','test-not-a-credential','ACTIVE');
CALL grant_application_role(NULL,1001,'SYSTEM_ADMIN',NULL,NULL,NULL,NULL,'Isolated test');
CALL grant_application_role(1001,1002,'OWNER',NULL,NULL,NULL,NULL,'Isolated test');
INSERT INTO facilities(id,created_by,code,name,address,ward_name) VALUES
 (1001,1002,'TEST_F1','Facility','Street 1','Ward 1'),
 (1002,1002,'TEST_F2','Facility Two','Street 2','Ward 2');
INSERT INTO employees(id,user_id,employee_code,full_name) VALUES(1001,1003,'TEST_E1','Test manager');

DELIMITER $$
CREATE PROCEDURE n01sport_smoke_invalid_grant()
BEGIN
    DECLARE rejected BOOL DEFAULT FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET rejected=TRUE;
        CALL grant_application_role(1001,1003,'FACILITY_MANAGER',1001,NULL,NULL,NULL,'Invalid appointment');
    END;
    CALL n01sport_smoke_assert(rejected,'Manager grant without appointment passed');
END$$
DELIMITER ;
CALL n01sport_smoke_invalid_grant();
DROP PROCEDURE n01sport_smoke_invalid_grant;

INSERT INTO facility_manager_assignments(id,facility_id,employee_id,appointed_by,decision_ref,starts_at)
VALUES(1001,1001,1001,1002,'TEST_DEC',UTC_TIMESTAMP(6)-INTERVAL 1 DAY);
CALL grant_application_role(1001,1003,'FACILITY_MANAGER',1001,NULL,1001,NULL,'Matching appointment');
CALL n01sport_smoke_assert(has_effective_role(1003,'FACILITY_MANAGER',1001,UTC_TIMESTAMP(6))
   AND NOT has_effective_role(1003,'FACILITY_MANAGER',1002,UTC_TIMESTAMP(6)),'Manager authority crosses facilities');
INSERT INTO customers(id,user_id,home_facility_id,full_name) VALUES(1001,1004,1001,'Test customer');
INSERT INTO sport_types(id,name) VALUES(1001,'Test futsal');
INSERT INTO courts(id,facility_id,sport_type_id,code,name) VALUES
 (1001,1001,1001,'TEST_C1','Court 1'),(1002,1001,1001,'TEST_C2','Court 2'),
 (1003,1001,1001,'TEST_C3','Court 3');
SET @vn_today=DATE(UTC_TIMESTAMP()+INTERVAL 7 HOUR);
SET @base=CAST(@vn_today+INTERVAL 2 DAY AS DATETIME)+INTERVAL 3 HOUR;
INSERT INTO court_hours(court_id,weekday,opens_at,closes_at,valid_from)
SELECT c.id,d.day_no,'06:00:00','23:00:00',@vn_today-INTERVAL 1 DAY
FROM (SELECT 1001 AS id UNION ALL SELECT 1002 UNION ALL SELECT 1003) c
CROSS JOIN (SELECT 1 AS day_no UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
            UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7) d;
INSERT INTO court_prices(court_id,proposed_by,decided_by,weekday,starts_time,ends_time,hourly_rate,valid_from,approval,decided_at)
SELECT h.court_id,1002,1002,h.weekday,'06:00:00','23:00:00',100000,@vn_today-INTERVAL 1 DAY,'APPROVED',UTC_TIMESTAMP(6)
FROM court_hours h;

CALL hold_booking('TEST_B1',1001,1001,NULL,@base,@base+INTERVAL 1 HOUR,NULL,NULL);
DELIMITER $$
CREATE PROCEDURE n01sport_smoke_overlaps(IN p_start DATETIME(6))
BEGIN
    DECLARE rejected BOOL DEFAULT FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET rejected=TRUE;
        CALL hold_booking('TEST_B_OVERLAP',1001,1001,NULL,p_start+INTERVAL 30 MINUTE,
                          p_start+INTERVAL 90 MINUTE,NULL,NULL);
    END;
    CALL n01sport_smoke_assert(rejected,'An overlapping booking was accepted');
    SET rejected=FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET rejected=TRUE;
        INSERT INTO court_blocks(court_id,created_by,starts_at,ends_at,reason)
        VALUES(1001,1003,p_start,p_start+INTERVAL 1 HOUR,'Repair');
    END;
    CALL n01sport_smoke_assert(rejected,'Maintenance overlapped an active booking');
    SET rejected=FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET rejected=TRUE;
        INSERT INTO court_hours(court_id,weekday,opens_at,closes_at,valid_from)
        VALUES(1001,1,'07:00:00','08:00:00',CURRENT_DATE);
    END;
    CALL n01sport_smoke_assert(rejected,'An overlapping opening period was accepted');
END$$
DELIMITER ;
CALL n01sport_smoke_overlaps(@base);
DROP PROCEDURE n01sport_smoke_overlaps;

CALL hold_booking('TEST_B2',1001,1001,NULL,@base+INTERVAL 1 HOUR,@base+INTERVAL 2 HOUR,NULL,NULL);
SELECT id INTO @b1 FROM bookings WHERE code='TEST_B1';
SELECT id INTO @b2 FROM bookings WHERE code='TEST_B2';
CALL create_payment_request(@b1,'test:pay1',100000);
CALL create_payment_request(@b1,'test:pay1',100000);
SELECT id INTO @pay1 FROM payments WHERE idempotency_key='test:pay1';
CALL attach_payment_gateway(@pay1,'test:provider1','demo QR');
CALL record_payment_callback(@pay1,'test:provider1','test:bad_amount',1,TRUE);
SELECT status INTO @state FROM bookings WHERE id=@b1;
CALL n01sport_smoke_assert(@state='PENDING_PAYMENT','Mismatched payment confirmed booking');
CALL record_payment_callback(@pay1,'test:provider1','test:event1',100000,TRUE);
CALL record_payment_callback(@pay1,'test:provider1','test:event1',100000,TRUE);
SELECT status INTO @state FROM bookings WHERE id=@b1;
CALL n01sport_smoke_assert(@state='CONFIRMED','Paid booking not confirmed');
SELECT COUNT(*) INTO @n FROM payment_events WHERE event_key='test:event1';
CALL n01sport_smoke_assert(@n=1,'Repeated callback created duplicate event');
CALL move_booking(@b2,1004,'CANCELLED','Test customer cancellation');

-- Construct an expired hold for the late callback test without waiting 15 minutes.
SET @created=UTC_TIMESTAMP(6)-INTERVAL 18 MINUTE;
INSERT INTO bookings(code,customer_id,court_id,start_at,end_at,court_fee,amount_due,created_at,expires_at)
VALUES('TEST_LATE',1001,1002,@base,@base+INTERVAL 1 HOUR,100000,100000,@created,@created+INTERVAL 15 MINUTE);
SET @late=LAST_INSERT_ID();
INSERT INTO payments(booking_id,idempotency_key,amount) VALUES(@late,'test:late',100000);
SET @paylate=LAST_INSERT_ID();
CALL record_payment_callback(@paylate,'test:provider_late','test:event_late',100000,TRUE);
SELECT status INTO @state FROM bookings WHERE id=@late;
SELECT status INTO @payment_state FROM payments WHERE id=@paylate;
CALL n01sport_smoke_assert(@state='EXPIRED' AND @payment_state='LATE_SUCCESS','Late callback was not quarantined');

CALL submit_refund_request(@pay1,1003,25000,'Facility fault','test:evidence1');
SELECT id INTO @request FROM refund_requests WHERE payment_id=@pay1;
CALL decide_refund_request(@request,1002,TRUE);
CALL create_refund_attempt(@request,'test:refund1',25000);
CALL create_refund_attempt(@request,'test:refund1',25000);
SELECT id INTO @refund FROM refunds WHERE attempt_key='test:refund1';
CALL settle_refund_attempt(@refund,'test:refund_provider1',25000,TRUE);
CALL settle_refund_attempt(@refund,'test:refund_provider1',25000,TRUE);
SELECT court_spend INTO @net FROM vw_customer_metrics WHERE customer_id=1001;
CALL n01sport_smoke_assert(@net=75000,'Customer view returned wrong net revenue');
SELECT SUM(signed_amount) INTO @net FROM vw_revenue WHERE category='COURT';
CALL n01sport_smoke_assert(@net=75000,'Revenue view included late or duplicate payment');

INSERT INTO products(id,sku,name) VALUES(1001,'TEST_SKU','Water');
INSERT INTO facility_inventory(id,facility_id,product_id,on_hand,unit_price) VALUES(1001,1001,1001,10,5000);
INSERT INTO sales_orders(id,facility_id,created_by,total_amount) VALUES(1001,1001,1003,10000);
INSERT INTO sales_order_lines(order_id,inventory_id,quantity,unit_price) VALUES(1001,1001,2,5000);
CALL settle_sale_payment(1001,1003,'test:sale1','CASH',10000);
CALL settle_sale_payment(1001,1003,'test:sale1','CASH',10000);
SELECT on_hand INTO @n FROM facility_inventory WHERE id=1001;
CALL n01sport_smoke_assert(@n=8,'Sale settlement decremented stock more than once');

INSERT INTO equipment_types(id,name) VALUES(1001,'Test racket');
INSERT INTO equipment_items(id,facility_id,equipment_type_id,asset_code,rental_rate,deposit_amount)
VALUES(1001,1001,1001,'TEST_ASSET',20000,40000);
INSERT INTO rental_orders(id,facility_id,customer_id,created_by,starts_at,ends_at)
VALUES(1001,1001,1001,1003,@base,@base+INTERVAL 1 HOUR);
INSERT INTO rental_order_lines(id,rental_id,equipment_id,rent_amount,deposit_amount) VALUES(1001,1001,1001,20000,40000);
UPDATE rental_order_lines SET handed_at=UTC_TIMESTAMP(6) WHERE id=1001;
UPDATE rental_order_lines SET returned_at=UTC_TIMESTAMP(6),return_condition='OK' WHERE id=1001;
SELECT condition_status INTO @state FROM equipment_items WHERE id=1001;
CALL n01sport_smoke_assert(@state='AVAILABLE','Returned asset did not become available');
INSERT INTO rental_transactions(rental_id,recorded_by,transaction_key,kind,method,amount,status,posted_at)
VALUES(1001,1003,'test:rent1','RENT','CASH',20000,'SUCCEEDED',UTC_TIMESTAMP(6)),
      (1001,1003,'test:deposit','DEPOSIT','CASH',40000,'SUCCEEDED',UTC_TIMESTAMP(6)),
      (1001,1003,'test:deposit-refund','DEPOSIT_REFUND','CASH',40000,'SUCCEEDED',UTC_TIMESTAMP(6));
SELECT SUM(signed_amount) INTO @net FROM vw_revenue WHERE category<>'COURT';
CALL n01sport_smoke_assert(@net=30000,'Equipment deposits were counted as revenue');
SELECT COUNT(*) INTO @n FROM vw_court_utilization WHERE court_id=1002 AND usage_date=@vn_today;
CALL n01sport_smoke_assert(@n=1,'Utilization view omitted open court');

-- Isolated historical visit fixture. The normal path into CHECKED_IN is move_booking().
SET @visit=UTC_TIMESTAMP(6)-INTERVAL 4 HOUR;
SET @visit_created=@visit-INTERVAL 30 MINUTE;
INSERT INTO bookings(code,customer_id,court_id,start_at,end_at,court_fee,amount_due,status,created_at,expires_at)
VALUES('TEST_VISIT',1001,1003,@visit,@visit+INTERVAL 1 HOUR,100000,100000,'CHECKED_IN',
       @visit_created,@visit_created+INTERVAL 15 MINUTE);
SET @visit_booking=LAST_INSERT_ID();
INSERT INTO payments(booking_id,idempotency_key,provider_ref,amount,status,received_at)
VALUES(@visit_booking,'test:visit','test:visit_provider',100000,'SUCCEEDED',@visit_created+INTERVAL 1 MINUTE);
SET @visit_pay=LAST_INSERT_ID();
INSERT INTO booking_status_history(booking_id,from_status,to_status,changed_at)
VALUES(@visit_booking,'PENDING_PAYMENT','CONFIRMED',@visit_created+INTERVAL 1 MINUTE);
INSERT INTO loyalty_rules(configured_by,vnd_per_point,starts_at)
VALUES(1002,1000,UTC_TIMESTAMP(6)-INTERVAL 1 DAY);
CALL move_booking(@visit_booking,1003,'COMPLETED','Finished visit');
SELECT id,balance INTO @loyalty,@n FROM loyalty_accounts WHERE customer_id=1001;
CALL n01sport_smoke_assert(@n=100,'Booking completion did not issue correct points');

INSERT INTO promotions(facility_id,code,is_enabled) VALUES(1001,'TEST_PROMO',TRUE);
SET @promo=LAST_INSERT_ID();
INSERT INTO promotion_versions(promotion_id,proposed_by,decided_by,name,discount_type,discount_value,
    min_subtotal,usage_limit,starts_at,ends_at,approval,decided_at)
VALUES(@promo,1002,1002,'Test discount','FIXED',10000,0,1,
    UTC_TIMESTAMP(6)-INTERVAL 1 DAY,UTC_TIMESTAMP(6)+INTERVAL 7 DAY,'APPROVED',UTC_TIMESTAMP(6));
SET @promo_version=LAST_INSERT_ID();
INSERT INTO reward_offers(promotion_id,points_cost) VALUES(@promo,20);
SET @offer=LAST_INSERT_ID();
CALL redeem_loyalty_reward(@loyalty,@offer,'TEST_VOUCHER',UTC_TIMESTAMP(6)+INTERVAL 1 DAY);
SELECT id INTO @voucher FROM reward_redemptions WHERE voucher_code='TEST_VOUCHER';
SELECT balance INTO @n FROM loyalty_accounts WHERE id=@loyalty;
CALL n01sport_smoke_assert(@n=80,'Reward redemption did not debit points');
CALL hold_booking('TEST_DISCOUNT',1001,1002,NULL,@base+INTERVAL 2 HOUR,@base+INTERVAL 3 HOUR,@promo_version,@voucher);
SELECT amount_due INTO @net FROM bookings WHERE code='TEST_DISCOUNT';
CALL n01sport_smoke_assert(@net=90000,'Booking quote did not apply fixed discount');
DELIMITER $$
CREATE PROCEDURE n01sport_smoke_limit(IN p_slot DATETIME(6), IN p_promotion BIGINT)
BEGIN
    DECLARE rejected BOOL DEFAULT FALSE;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET rejected=TRUE;
        CALL hold_booking('TEST_QUOTA',1001,1002,NULL,p_slot,p_slot+INTERVAL 1 HOUR,p_promotion,NULL);
    END;
    CALL n01sport_smoke_assert(rejected,'Promotion limit ignored an active hold');
END$$
DELIMITER ;
CALL n01sport_smoke_limit(@base+INTERVAL 4 HOUR,@promo_version);
DROP PROCEDURE n01sport_smoke_limit;

CALL submit_refund_request(@visit_pay,1003,25000,'Facility fault','test:evidence_visit');
SELECT id INTO @visit_request FROM refund_requests WHERE payment_id=@visit_pay;
CALL decide_refund_request(@visit_request,1002,TRUE);
CALL create_refund_attempt(@visit_request,'test:refund_visit',25000);
SELECT id INTO @visit_refund FROM refunds WHERE attempt_key='test:refund_visit';
CALL settle_refund_attempt(@visit_refund,'test:refund_provider_visit',25000,TRUE);
CALL settle_refund_attempt(@visit_refund,'test:refund_provider_visit',25000,TRUE);
SELECT balance INTO @n FROM loyalty_accounts WHERE id=@loyalty;
CALL n01sport_smoke_assert(@n=-20,'Refund must reverse earned points exactly once');

UPDATE facility_manager_assignments SET ends_at=UTC_TIMESTAMP(6) WHERE id=1001;
CALL n01sport_smoke_assert(NOT has_effective_role(1003,'FACILITY_MANAGER',1001,UTC_TIMESTAMP(6)),
   'Expired manager assignment kept its authority');

DROP PROCEDURE n01sport_smoke_assert;
SELECT 'PASS | import, promotion, loyalty, booking, payment, refund, stock, rental, reports, role scope' AS result;
