-- 03 Đặt sân và thanh toán
USE n01sport_dev;

CREATE TABLE customers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE,
    home_facility_id BIGINT,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Hồ sơ khách sử dụng dịch vụ';

CREATE TABLE bookings (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(32) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    customer_id BIGINT NOT NULL,
    court_id BIGINT NOT NULL,
    series_id BIGINT,
    handled_by BIGINT,
    start_at DATETIME(6) NOT NULL,
    end_at DATETIME(6) NOT NULL,
    court_fee DECIMAL(14,0) NOT NULL CHECK (court_fee >= 0),
    discount_amount DECIMAL(14,0) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    amount_due DECIMAL(14,0) NOT NULL CHECK (amount_due >= 0),
    status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING_PAYMENT',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    expires_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6) + INTERVAL 15 MINUTE),
    operations_note TEXT,
    CHECK (start_at < end_at),
    CHECK (expires_at = created_at + INTERVAL 15 MINUTE),
    CHECK (amount_due = court_fee - discount_amount),
    CHECK (status IN ('PENDING_PAYMENT', 'CONFIRMED', 'CHECKED_IN', 'NO_SHOW', 'COMPLETED', 'CANCELLED', 'EXPIRED'))
) ENGINE=InnoDB COMMENT='Lượt đặt sân và số tiền đã chốt';

CREATE TABLE payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    booking_id BIGINT NOT NULL,
    idempotency_key VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    provider_ref VARCHAR(120) COLLATE utf8mb4_0900_bin UNIQUE,
    qr_payload TEXT,
    amount DECIMAL(14,0) NOT NULL CHECK (amount >= 0),
    status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    received_at DATETIME(6),
    CHECK (status NOT IN ('SUCCEEDED', 'LATE_SUCCESS') OR (provider_ref IS NOT NULL AND received_at IS NOT NULL)),
    CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'LATE_SUCCESS'))
) ENGINE=InnoDB COMMENT='Yêu cầu và lần giao dịch thanh toán QR';

CREATE TABLE coach_profiles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    facility_id BIGINT NOT NULL,
    reviewed_by BIGINT,
    evidence_ref TEXT NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    submitted_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    reviewed_at DATETIME(6),
    valid_until DATETIME(6),
    review_note TEXT,
    CHECK ((status = 'PENDING' AND reviewed_by IS NULL AND reviewed_at IS NULL) OR (status <> 'PENDING' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
    CHECK (valid_until IS NULL OR valid_until > submitted_at),
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB COMMENT='Lần đăng ký và xét duyệt hồ sơ HLV';

CREATE TABLE booking_series (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    coach_profile_id BIGINT NOT NULL,
    preferred_court_id BIGINT NOT NULL,
    first_date DATE NOT NULL,
    last_date DATE NOT NULL,
    starts_time TIME NOT NULL,
    ends_time TIME NOT NULL,
    recurrence_rule TEXT NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (first_date <= last_date),
    CHECK (starts_time < ends_time)
) ENGINE=InnoDB COMMENT='Nhóm lịch thuê sân định kỳ';

CREATE TABLE payment_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    payment_id BIGINT NOT NULL,
    event_key VARCHAR(150) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    reported_amount DECIMAL(14,0) NOT NULL CHECK (reported_amount >= 0),
    received_at DATETIME(6) NOT NULL,
    outcome VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL
) ENGINE=InnoDB COMMENT='Sự kiện từ cổng thanh toán đã đối chiếu';

CREATE TABLE booking_price_lines (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    booking_id BIGINT NOT NULL,
    court_price_id BIGINT NOT NULL,
    start_at DATETIME(6) NOT NULL,
    end_at DATETIME(6) NOT NULL,
    hourly_rate DECIMAL(14,0) NOT NULL CHECK (hourly_rate >= 0),
    line_amount DECIMAL(14,0) NOT NULL CHECK (line_amount >= 0),
    CHECK (start_at < end_at)
) ENGINE=InnoDB COMMENT='Các đoạn giá đã chốt của một booking';

CREATE TABLE booking_status_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    booking_id BIGINT NOT NULL,
    changed_by BIGINT,
    from_status VARCHAR(24) COLLATE utf8mb4_0900_bin,
    to_status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    changed_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    reason TEXT,
    CHECK (from_status IS NULL OR from_status <> to_status)
) ENGINE=InnoDB COMMENT='Lịch sử chuyển trạng thái và check-in';

CREATE TABLE refund_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    payment_id BIGINT NOT NULL,
    requested_by BIGINT NOT NULL,
    decided_by BIGINT,
    amount DECIMAL(14,0) NOT NULL CHECK (amount >= 0),
    reason TEXT NOT NULL,
    evidence_ref TEXT NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    requested_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    decided_at DATETIME(6),
    CHECK ((status = 'PENDING' AND decided_by IS NULL AND decided_at IS NULL) OR (status <> 'PENDING' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)),
    CHECK (TRIM(reason) <> '' AND TRIM(evidence_ref) <> ''),
    CHECK (amount > 0),
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB COMMENT='Đề xuất hoàn ngoại lệ có bằng chứng';

CREATE TABLE refunds (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id BIGINT NOT NULL,
    attempt_key VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    provider_ref VARCHAR(120) COLLATE utf8mb4_0900_bin UNIQUE,
    amount DECIMAL(14,0) NOT NULL CHECK (amount >= 0),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    settled_at DATETIME(6),
    CHECK (status <> 'SUCCEEDED' OR (settled_at IS NOT NULL AND provider_ref IS NOT NULL)),
    CHECK (amount > 0),
    CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED'))
) ENGINE=InnoDB COMMENT='Lần giao dịch hoàn tiền sau phê duyệt';
