-- 01 Quản lý tài khoản
USE n01sport_dev;

CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(254) UNIQUE,
    phone VARCHAR(20) UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    password_hash VARCHAR(255) COLLATE utf8mb4_0900_bin NOT NULL,
    status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING_VERIFICATION',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (email IS NOT NULL OR phone IS NOT NULL),
    CHECK (email IS NULL OR (CAST(email AS BINARY) = CAST(LOWER(TRIM(email)) AS BINARY) AND email <> '')),
    CHECK (phone IS NULL OR REGEXP_LIKE(phone, '^[+]?[0-9]{7,15}$', 'c')),
    CHECK (TRIM(password_hash) <> ''),
    CHECK (status IN ('ACTIVE', 'PENDING_VERIFICATION', 'LOCKED', 'DISABLED'))
) ENGINE=InnoDB COMMENT='Tài khoản';

CREATE TABLE auth_sessions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    token_hash VARCHAR(255) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6),
    CHECK (expires_at > created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
) ENGINE=InnoDB COMMENT='Phiên đăng nhập';

CREATE TABLE auth_challenges (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT,
    purpose VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    destination VARCHAR(254) NOT NULL,
    secret_hash VARCHAR(255) COLLATE utf8mb4_0900_bin NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    used_at DATETIME(6)
) ENGINE=InnoDB COMMENT='Xác minh liên hệ và đặt lại mật khẩu';
