-- Dữ liệu mẫu N01SPORT. Có thể chạy lại để bổ sung phần còn thiếu.
-- Các bản ghi đã có được tìm theo email, mã cơ sở/sân, tên môn, SKU và FK.
-- Tài khoản mẫu chứa băm giả. Tạo tài khoản qua backend để thử đăng nhập.
USE n01sport_dev;

DROP PROCEDURE IF EXISTS n01sport_seed_demo_v2;

DELIMITER $$
CREATE PROCEDURE n01sport_seed_demo_v2()
SQL SECURITY INVOKER
BEGIN
    DECLARE owner_id BIGINT;
    DECLARE user_id_value BIGINT;
    DECLARE facility_id_value BIGINT;
    DECLARE customer_id_value BIGINT;
    DECLARE sport_id BIGINT;
    DECLARE court_id_value BIGINT;
    DECLARE product_id BIGINT;
    DECLARE owner_role BIGINT;
    DECLARE local_day DATE;
    DECLARE day_no INT DEFAULT 1;
    DECLARE locked INT DEFAULT 0;
    DECLARE started BOOL DEFAULT FALSE;
    DECLARE lock_name VARCHAR(64);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF started THEN ROLLBACK; END IF;
        IF locked=1 THEN DO RELEASE_LOCK(lock_name); END IF;
        RESIGNAL;
    END;
    SET lock_name=CONCAT(DATABASE(),':seed-demo-v2');
    SELECT GET_LOCK(lock_name,10) INTO locked;
    IF COALESCE(locked,0)<>1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Another demo seed is running; retry later';
    END IF;
    START TRANSACTION;
    SET started=TRUE;
    SELECT MAX(id) INTO owner_role FROM roles WHERE code='OWNER';
    IF owner_role IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Install the default roles before loading demo data';
    END IF;
    SELECT MAX(id) INTO owner_id FROM users WHERE email='demo.owner@example.invalid';
    IF owner_id IS NULL THEN
        INSERT INTO users(email,full_name,password_hash,status)
        VALUES('demo.owner@example.invalid','Chủ cơ sở mẫu','DEMO-NO-LOGIN','ACTIVE');
        SET owner_id=LAST_INSERT_ID();
    END IF;
    IF NOT EXISTS(SELECT 1 FROM user_role_grants WHERE user_id=owner_id AND role_id=owner_role
                  AND facility_id IS NULL AND revoked_at IS NULL) THEN
        INSERT INTO user_role_grants(user_id,role_id,reason)
        VALUES(owner_id,owner_role,'Dữ liệu minh họa local');
    END IF;
    SELECT MAX(id) INTO user_id_value FROM users WHERE email='demo.customer@example.invalid';
    IF user_id_value IS NULL THEN
        INSERT INTO users(email,full_name,password_hash,status)
        VALUES('demo.customer@example.invalid','Khách hàng mẫu','DEMO-NO-LOGIN','ACTIVE');
        SET user_id_value=LAST_INSERT_ID();
    END IF;
    SELECT MAX(id) INTO facility_id_value FROM facilities WHERE code='DEMO_DN';
    IF facility_id_value IS NULL THEN
        INSERT INTO facilities(created_by,code,name,address,ward_name)
        VALUES(owner_id,'DEMO_DN','Cơ sở thể thao mẫu','Địa chỉ minh họa, Đà Nẵng','Phường mẫu');
        SET facility_id_value=LAST_INSERT_ID();
    END IF;
    SELECT MAX(id) INTO customer_id_value FROM customers WHERE user_id=user_id_value;
    IF customer_id_value IS NULL THEN
        INSERT INTO customers(user_id,home_facility_id,full_name)
        VALUES(user_id_value,facility_id_value,'Khách hàng mẫu');
        SET customer_id_value=LAST_INSERT_ID();
    END IF;
    SELECT MAX(id) INTO sport_id FROM sport_types WHERE name='Cầu lông';
    IF sport_id IS NULL THEN
        INSERT INTO sport_types(name) VALUES('Cầu lông');
        SET sport_id=LAST_INSERT_ID();
    END IF;
    SELECT MAX(id) INTO court_id_value FROM courts WHERE facility_id=facility_id_value AND code='DEMO_A01';
    IF court_id_value IS NULL THEN
        INSERT INTO courts(facility_id,sport_type_id,code,name)
        VALUES(facility_id_value,sport_id,'DEMO_A01','Sân mẫu A01');
        SET court_id_value=LAST_INSERT_ID();
    END IF;
    SET local_day=DATE(UTC_TIMESTAMP()+INTERVAL 7 HOUR);
    WHILE day_no<=7 DO
        IF NOT EXISTS(SELECT 1 FROM court_hours WHERE court_id=court_id_value AND weekday=day_no
                      AND (valid_to IS NULL OR valid_to>local_day)) THEN
            INSERT INTO court_hours(court_id,weekday,opens_at,closes_at,valid_from)
            VALUES(court_id_value,day_no,'06:00:00','23:00:00',local_day);
        END IF;
        IF NOT EXISTS(SELECT 1 FROM court_prices WHERE court_id=court_id_value AND weekday=day_no
                      AND approval='APPROVED' AND (valid_to IS NULL OR valid_to>local_day)) THEN
            INSERT INTO court_prices(court_id,proposed_by,decided_by,weekday,starts_time,ends_time,
                                     hourly_rate,valid_from,approval,decided_at)
            VALUES(court_id_value,owner_id,owner_id,day_no,'06:00:00','23:00:00',
                   100000,local_day,'APPROVED',UTC_TIMESTAMP(6));
        END IF;
        SET day_no=day_no+1;
    END WHILE;
    SELECT MAX(id) INTO product_id FROM products WHERE sku='DEMO_WATER';
    IF product_id IS NULL THEN
        INSERT INTO products(sku,name) VALUES('DEMO_WATER','Nước uống mẫu');
        SET product_id=LAST_INSERT_ID();
    END IF;
    IF NOT EXISTS(SELECT 1 FROM facility_inventory WHERE facility_id=facility_id_value AND product_id=product_id) THEN
        INSERT INTO facility_inventory(facility_id,product_id,on_hand,unit_price)
        VALUES(facility_id_value,product_id,20,10000);
    END IF;
    COMMIT;
    SET started=FALSE;
    DO RELEASE_LOCK(lock_name);
    SET locked=0;
    SELECT facility_id_value AS facility_id,court_id_value AS court_id,customer_id_value AS customer_id,
           'OK' AS seed_result;
END$$
DELIMITER ;

CALL n01sport_seed_demo_v2();
DROP PROCEDURE n01sport_seed_demo_v2;
