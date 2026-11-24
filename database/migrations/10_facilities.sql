-- 10 Quản lý cơ sở
USE n01sport_dev;

CREATE TABLE facilities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    created_by BIGINT NOT NULL,
    code VARCHAR(32) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255) NOT NULL,
    district_label VARCHAR(80),
    ward_name VARCHAR(100) NOT NULL,
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    contact_phone VARCHAR(20),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (((latitude IS NOT NULL) + (longitude IS NOT NULL)) IN (0, 2)),
    CHECK (latitude BETWEEN -90 AND 90),
    CHECK (longitude BETWEEN -180 AND 180),
    CHECK (status IN ('ACTIVE', 'SUSPENDED', 'INACTIVE'))
) ENGINE=InnoDB COMMENT='Thông tin và trạng thái cơ sở thể thao';

CREATE TABLE facility_suspensions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    created_by BIGINT NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6),
    reason TEXT NOT NULL,
    CHECK (ends_at IS NULL OR starts_at < ends_at)
) ENGINE=InnoDB COMMENT='Lịch sử và khoảng thời gian tạm ngừng';

CREATE TABLE facility_manager_assignments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    employee_id BIGINT NOT NULL,
    appointed_by BIGINT NOT NULL,
    decision_ref VARCHAR(150) NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6),
    CHECK (ends_at IS NULL OR starts_at < ends_at)
) ENGINE=InnoDB COMMENT='Quyết định và lịch sử bổ nhiệm quản lý chính';
