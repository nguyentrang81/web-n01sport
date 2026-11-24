USE n01sport_dev;

START TRANSACTION;
-- Danh mục tham chiếu tối thiểu


-- Minimal reference data. The application owner defines VIP thresholds, permissions,
-- and the earning rate before enabling those features.
INSERT INTO roles (code,name) VALUES
    ('CUSTOMER','Khách hàng'),
    ('COACH','Huấn luyện viên'),
    ('OWNER','Chủ hệ thống'),
    ('FACILITY_MANAGER','Quản lý cơ sở'),
    ('STAFF','Nhân viên'),
    ('SYSTEM_ADMIN','Quản trị viên hệ thống');

INSERT INTO loyalty_tiers (code,name,min_points) VALUES ('STANDARD','Thành viên tiêu chuẩn',0);


COMMIT;
