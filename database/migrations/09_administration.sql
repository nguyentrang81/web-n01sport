-- 09 Quản trị hệ thống
USE n01sport_dev;

CREATE TABLE roles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(32) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL
) ENGINE=InnoDB COMMENT='Danh mục vai trò hệ thống';

CREATE TABLE role_permissions (
    role_id BIGINT NOT NULL,
    permission_id BIGINT NOT NULL,
    PRIMARY KEY (role_id, permission_id)
) ENGINE=InnoDB COMMENT='Bảng nối giữa vai trò và quyền';

CREATE TABLE permissions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    description TEXT NOT NULL
) ENGINE=InnoDB COMMENT='Danh mục quyền thao tác';

CREATE TABLE user_role_grants (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    facility_id BIGINT,
    coach_profile_id BIGINT,
    manager_assignment_id BIGINT,
    staff_assignment_id BIGINT,
    granted_by BIGINT,
    revoked_by BIGINT,
    granted_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    revoked_at DATETIME(6),
    reason TEXT,
    CHECK (revoked_at IS NULL OR revoked_at >= granted_at),
    CHECK (revoked_by IS NULL OR revoked_at IS NOT NULL),
    CHECK (((coach_profile_id IS NOT NULL) + (manager_assignment_id IS NOT NULL) + (staff_assignment_id IS NOT NULL)) <= 1)
) ENGINE=InnoDB COMMENT='Lịch sử cấp và thu hồi vai trò theo phạm vi';

CREATE TABLE system_settings (
    `key` VARCHAR(80) COLLATE utf8mb4_0900_bin PRIMARY KEY,
    value JSON NOT NULL,
    updated_by BIGINT NOT NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Cấu hình hệ thống';

CREATE TABLE backup_jobs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source_backup_id BIGINT,
    requested_by BIGINT NOT NULL,
    kind VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    scope JSON NOT NULL,
    storage_ref TEXT,
    integrity_ref VARCHAR(128),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    finished_at DATETIME(6),
    CHECK ((kind = 'BACKUP' AND source_backup_id IS NULL) OR (kind = 'RESTORE' AND source_backup_id IS NOT NULL)),
    CHECK (status IN ('PENDING', 'RUNNING', 'SUCCEEDED', 'FAILED'))
) ENGINE=InnoDB COMMENT='Tác vụ sao lưu và phục hồi';

CREATE TABLE audit_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    actor_id BIGINT,
    facility_id BIGINT,
    action VARCHAR(80) COLLATE utf8mb4_0900_bin NOT NULL,
    entity_type VARCHAR(60) COLLATE utf8mb4_0900_bin NOT NULL,
    entity_key VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL,
    details JSON,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Nhật ký thay đổi dữ liệu';

CREATE TABLE login_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT,
    attempted_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    outcome VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    ip_address VARCHAR(45)
) ENGINE=InnoDB COMMENT='Nhật ký kết quả đăng nhập';

CREATE TABLE system_errors (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    component VARCHAR(80) NOT NULL,
    severity VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    error_code VARCHAR(60),
    message TEXT NOT NULL,
    occurred_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Nhật ký lỗi và chẩn đoán';
