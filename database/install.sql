-- N01SPORT | MySQL 8.0 | Database n01sport_dev
-- Cài một lần bằng install.sql hoặc các migration 00–15 theo thứ tự.
-- DATETIME(6) lưu UTC, lịch sân và khung giá dùng giờ địa phương UTC+07:00.

-- 00_database.sql
-- MySQL 8.0 dành cho N01SPORT.
CREATE DATABASE n01sport_dev
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE n01sport_dev;

-- 01_accounts.sql
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

-- 02_courts.sql
-- 02 Quản lý sân thể thao
USE n01sport_dev;

CREATE TABLE courts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    sport_type_id BIGINT NOT NULL,
    code VARCHAR(30) COLLATE utf8mb4_0900_bin NOT NULL,
    name VARCHAR(120) NOT NULL,
    description TEXT,
    status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (facility_id, code),
    CHECK (status IN ('ACTIVE', 'INACTIVE'))
) ENGINE=InnoDB COMMENT='Danh mục sân';

CREATE TABLE sport_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB COMMENT='Danh mục môn thể thao';

CREATE TABLE court_images (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    court_id BIGINT NOT NULL,
    image_url TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    CHECK (sort_order >= 0)
) ENGINE=InnoDB COMMENT='Ảnh giới thiệu sân';

CREATE TABLE court_hours (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    court_id BIGINT NOT NULL,
    weekday SMALLINT NOT NULL,
    opens_at TIME NOT NULL,
    closes_at TIME NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE,
    CHECK (weekday BETWEEN 1 AND 7),
    CHECK (opens_at < closes_at),
    CHECK (valid_to IS NULL OR valid_from < valid_to)
) ENGINE=InnoDB COMMENT='Lịch hoạt động theo thứ và hiệu lực';

CREATE TABLE court_blocks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    court_id BIGINT NOT NULL,
    created_by BIGINT NOT NULL,
    maintenance_id BIGINT,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    reason TEXT NOT NULL,
    released_at DATETIME(6),
    CHECK (starts_at < ends_at),
    CHECK (released_at IS NULL OR released_at <= ends_at)
) ENGINE=InnoDB COMMENT='Khoảng thời gian tạm chặn sân';

CREATE TABLE court_prices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    court_id BIGINT NOT NULL,
    supersedes_id BIGINT,
    proposed_by BIGINT NOT NULL,
    decided_by BIGINT,
    weekday SMALLINT NOT NULL,
    starts_time TIME NOT NULL,
    ends_time TIME NOT NULL,
    hourly_rate DECIMAL(14,0) NOT NULL CHECK (hourly_rate >= 0),
    valid_from DATE NOT NULL,
    valid_to DATE,
    approval VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    decided_at DATETIME(6),
    decision_note TEXT,
    CHECK (weekday BETWEEN 1 AND 7),
    CHECK (starts_time < ends_time),
    CHECK (valid_to IS NULL OR valid_from < valid_to),
    CHECK ((approval = 'PENDING' AND decided_by IS NULL AND decided_at IS NULL) OR (approval <> 'PENDING' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)),
    CHECK (approval IN ('PENDING', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB COMMENT='Phiên bản giá sân và quyết định xét duyệt';

CREATE TABLE court_amenities (
    court_id BIGINT NOT NULL,
    amenity_id BIGINT NOT NULL,
    PRIMARY KEY (court_id, amenity_id)
) ENGINE=InnoDB COMMENT='Bảng nối giữa sân và tiện ích';

CREATE TABLE amenities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE
) ENGINE=InnoDB COMMENT='Danh mục tiện ích';

-- 03_booking_payments.sql
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

-- 04_services.sql
-- 04 Quản lý dịch vụ
USE n01sport_dev;

CREATE TABLE products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true
) ENGINE=InnoDB COMMENT='Danh mục hàng hóa bán tại sân';

CREATE TABLE facility_inventory (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    on_hand INTEGER NOT NULL DEFAULT 0,
    unit_price DECIMAL(14,0) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (facility_id, product_id),
    CHECK (on_hand >= 0)
) ENGINE=InnoDB COMMENT='Tồn kho và giá theo mặt hàng tại cơ sở';

CREATE TABLE sales_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    customer_id BIGINT,
    booking_id BIGINT,
    created_by BIGINT NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(14,0) NOT NULL CHECK (total_amount >= 0),
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (status IN ('PENDING', 'PAID', 'CANCELLED'))
) ENGINE=InnoDB COMMENT='Đơn bán hàng';

CREATE TABLE sales_order_lines (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    inventory_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(14,0) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (order_id, inventory_id),
    CHECK (quantity > 0)
) ENGINE=InnoDB COMMENT='Số lượng và giá bán chốt';

CREATE TABLE sales_payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    recorded_by BIGINT NOT NULL,
    payment_key VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    method VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    amount DECIMAL(14,0) NOT NULL CHECK (amount >= 0),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    paid_at DATETIME(6),
    CHECK (status <> 'SUCCEEDED' OR paid_at IS NOT NULL),
    CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED'))
) ENGINE=InnoDB COMMENT='Thanh toán đơn bán hàng';

CREATE TABLE equipment_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE
) ENGINE=InnoDB COMMENT='Danh mục loại dụng cụ';

CREATE TABLE equipment_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    equipment_type_id BIGINT NOT NULL,
    asset_code VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    rental_rate DECIMAL(14,0) NOT NULL CHECK (rental_rate >= 0),
    deposit_amount DECIMAL(14,0) NOT NULL CHECK (deposit_amount >= 0),
    condition_status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'AVAILABLE',
    CHECK (condition_status IN ('AVAILABLE', 'IN_USE', 'DAMAGED', 'LOST', 'RETIRED'))
) ENGINE=InnoDB COMMENT='Từng dụng cụ cho thuê';

CREATE TABLE rental_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    booking_id BIGINT,
    created_by BIGINT NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    status VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (starts_at < ends_at),
    CHECK (status IN ('PENDING', 'HANDED_OVER', 'RETURNED', 'CANCELLED'))
) ENGINE=InnoDB COMMENT='Phiếu thuê dụng cụ';

CREATE TABLE rental_order_lines (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    rental_id BIGINT NOT NULL,
    equipment_id BIGINT NOT NULL,
    rent_amount DECIMAL(14,0) NOT NULL CHECK (rent_amount >= 0),
    deposit_amount DECIMAL(14,0) NOT NULL CHECK (deposit_amount >= 0),
    handed_at DATETIME(6),
    returned_at DATETIME(6),
    return_condition VARCHAR(24) COLLATE utf8mb4_0900_bin,
    damage_amount DECIMAL(14,0) NOT NULL DEFAULT 0 CHECK (damage_amount >= 0),
    UNIQUE (rental_id, equipment_id),
    CHECK (returned_at IS NULL OR (handed_at IS NOT NULL AND returned_at >= handed_at))
) ENGINE=InnoDB COMMENT='Bàn giao, trả và bồi thường từng dụng cụ';

CREATE TABLE rental_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    rental_id BIGINT NOT NULL,
    recorded_by BIGINT NOT NULL,
    transaction_key VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    kind VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    method VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    amount DECIMAL(14,0) NOT NULL CHECK (amount >= 0),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    posted_at DATETIME(6),
    CHECK (kind IN ('RENT','DEPOSIT','DEPOSIT_REFUND','DAMAGE_COMPENSATION')),
    CHECK (status <> 'SUCCEEDED' OR posted_at IS NOT NULL),
    CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED'))
) ENGINE=InnoDB COMMENT='Thu tiền thuê, thu cọc, hoàn cọc hoặc bồi thường';

CREATE TABLE technical_tickets (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    court_id BIGINT,
    equipment_id BIGINT,
    reported_by BIGINT NOT NULL,
    resolved_by BIGINT,
    priority VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'OPEN',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    resolved_at DATETIME(6),
    CHECK (((court_id IS NOT NULL) + (equipment_id IS NOT NULL)) >= 1),
    CHECK (status <> 'CLOSED' OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL)),
    CHECK (status IN ('OPEN', 'IN_PROGRESS', 'CLOSED', 'REOPENED'))
) ENGINE=InnoDB COMMENT='Phiếu sự cố sân hoặc thiết bị';

-- 05_staff.sql
-- 05 Quản lý nhân sự
USE n01sport_dev;

CREATE TABLE employees (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNIQUE,
    employee_code VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (status IN ('ACTIVE', 'INACTIVE'))
) ENGINE=InnoDB COMMENT='Hồ sơ nhân viên';

CREATE TABLE facility_staff_assignments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT NOT NULL,
    employee_id BIGINT NOT NULL,
    assigned_by BIGINT NOT NULL,
    position_code VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6),
    end_reason TEXT,
    CHECK (position_code IN ('RECEPTIONIST','TECHNICAL','CLEANING')),
    CHECK (ends_at IS NULL OR starts_at < ends_at)
) ENGINE=InnoDB COMMENT='Lịch sử phân công vị trí thông thường';

CREATE TABLE staff_shifts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    staff_assignment_id BIGINT NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    CHECK (starts_at < ends_at)
) ENGINE=InnoDB COMMENT='Ca làm theo phân công';

CREATE TABLE account_access_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    staff_assignment_id BIGINT NOT NULL,
    requested_by BIGINT NOT NULL,
    resolved_by BIGINT,
    request_type VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    reason TEXT NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    resolved_at DATETIME(6),
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB COMMENT='Yêu cầu mở hoặc khóa quyền đăng nhập';

CREATE TABLE technical_assignments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    ticket_id BIGINT NOT NULL,
    staff_assignment_id BIGINT NOT NULL,
    assigned_by BIGINT NOT NULL,
    assigned_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    due_at DATETIME(6) NOT NULL,
    accepted_at DATETIME(6),
    closed_at DATETIME(6),
    CHECK (assigned_at < due_at),
    CHECK (accepted_at IS NULL OR accepted_at >= assigned_at)
) ENGINE=InnoDB COMMENT='Lịch sử giao nhiệm vụ kỹ thuật';

CREATE TABLE technical_updates (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    assignment_id BIGINT NOT NULL,
    update_type VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
    details TEXT NOT NULL,
    evidence_ref TEXT,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Báo cáo hiện trạng và kết quả kỹ thuật';

CREATE TABLE maintenance_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    assignment_id BIGINT NOT NULL,
    decided_by BIGINT,
    details TEXT NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    decided_at DATETIME(6),
    CHECK (starts_at < ends_at),
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB COMMENT='Đề xuất bảo trì từ nhiệm vụ kỹ thuật';

CREATE TABLE cleaning_tasks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    shift_id BIGINT NOT NULL,
    court_id BIGINT,
    assigned_by BIGINT NOT NULL,
    area_label VARCHAR(160),
    details TEXT NOT NULL,
    priority VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    assigned_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    scheduled_at DATETIME(6) NOT NULL,
    accepted_at DATETIME(6),
    started_at DATETIME(6),
    completed_at DATETIME(6),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'ASSIGNED',
    result TEXT,
    CHECK (((court_id IS NOT NULL) + (area_label IS NOT NULL)) >= 1),
    CHECK (started_at IS NULL OR (accepted_at IS NOT NULL AND started_at >= accepted_at)),
    CHECK (completed_at IS NULL OR (started_at IS NOT NULL AND completed_at >= started_at)),
    CHECK (status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'))
) ENGINE=InnoDB COMMENT='Công việc vệ sinh giao theo ca';

-- 06_promotions_loyalty.sql
-- 06 Khuyến mãi và khách hàng thân thiết
USE n01sport_dev;

CREATE TABLE promotions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    facility_id BIGINT,
    code VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    is_enabled BOOLEAN NOT NULL DEFAULT false
) ENGINE=InnoDB COMMENT='Mã chương trình và phạm vi áp dụng';

CREATE TABLE promotion_versions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    promotion_id BIGINT NOT NULL,
    proposed_by BIGINT NOT NULL,
    decided_by BIGINT,
    name VARCHAR(160) NOT NULL,
    discount_type VARCHAR(12) COLLATE utf8mb4_0900_bin NOT NULL,
    discount_value DECIMAL(14,2) NOT NULL,
    min_subtotal DECIMAL(14,0) NOT NULL CHECK (min_subtotal >= 0),
    usage_limit INTEGER,
    rules JSON,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    approval VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    decided_at DATETIME(6),
    decision_note TEXT,
    CHECK (discount_type IN ('FIXED','PERCENT')),
    CHECK (discount_value > 0 AND (discount_type <> 'PERCENT' OR discount_value <= 100)),
    CHECK (discount_type <> 'FIXED' OR discount_value = TRUNCATE(discount_value, 0)),
    CHECK (usage_limit IS NULL OR usage_limit > 0),
    CHECK (starts_at < ends_at),
    CHECK ((approval = 'PENDING' AND decided_by IS NULL AND decided_at IS NULL) OR (approval <> 'PENDING' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)),
    CHECK (approval IN ('PENDING', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB COMMENT='Điều kiện chương trình và quyết định xét duyệt';

CREATE TABLE promotion_usages (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    booking_id BIGINT NOT NULL UNIQUE,
    promotion_version_id BIGINT NOT NULL,
    redemption_id BIGINT,
    discount_amount DECIMAL(14,0) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'HELD',
    CHECK (status IN ('HELD', 'USED', 'RELEASED'))
) ENGINE=InnoDB COMMENT='Lượt giữ hoặc dùng mã và mức giảm chốt';

CREATE TABLE loyalty_tiers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL,
    min_points INTEGER NOT NULL DEFAULT 0,
    CHECK (min_points >= 0)
) ENGINE=InnoDB COMMENT='Danh mục hạng thành viên gồm VIP';

CREATE TABLE loyalty_accounts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT NOT NULL UNIQUE,
    tier_id BIGINT NOT NULL,
    balance INTEGER NOT NULL DEFAULT 0
) ENGINE=InnoDB COMMENT='Ví điểm của khách hàng';

CREATE TABLE point_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    loyalty_account_id BIGINT NOT NULL,
    booking_id BIGINT,
    redemption_id BIGINT,
    rule_id BIGINT,
    dedup_key VARCHAR(100) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    kind VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
    points_delta INTEGER NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK ((kind = 'EARN' AND booking_id IS NOT NULL AND rule_id IS NOT NULL AND redemption_id IS NULL AND points_delta > 0) OR (kind = 'REVERSAL' AND booking_id IS NOT NULL AND redemption_id IS NULL AND points_delta < 0) OR (kind = 'REDEEM' AND redemption_id IS NOT NULL AND booking_id IS NULL AND rule_id IS NULL AND points_delta < 0))
) ENGINE=InnoDB COMMENT='Sổ biến động điểm';

CREATE TABLE loyalty_rules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    configured_by BIGINT NOT NULL,
    vnd_per_point INTEGER NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6),
    CHECK (vnd_per_point > 0),
    CHECK (ends_at IS NULL OR starts_at < ends_at)
) ENGINE=InnoDB COMMENT='Phiên bản quy tắc quy đổi tiền thành điểm';

CREATE TABLE reward_offers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    promotion_id BIGINT NOT NULL,
    points_cost INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    CHECK (points_cost > 0)
) ENGINE=InnoDB COMMENT='Danh mục ưu đãi đổi điểm';

CREATE TABLE reward_redemptions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    loyalty_account_id BIGINT NOT NULL,
    reward_offer_id BIGINT NOT NULL,
    voucher_code VARCHAR(60) COLLATE utf8mb4_0900_bin NOT NULL UNIQUE,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    expires_at DATETIME(6) NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'ISSUED',
    CHECK (expires_at > created_at),
    CHECK (status IN ('ISSUED', 'USED', 'REVOKED'))
) ENGINE=InnoDB COMMENT='Mã ưu đãi đã cấp cho khách';

-- 07_notifications_support.sql
-- 07 Thông báo và tương tác
USE n01sport_dev;

CREATE TABLE notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    booking_id BIGINT,
    payment_id BIGINT,
    court_block_id BIGINT,
    facility_id BIGINT,
    kind VARCHAR(24) COLLATE utf8mb4_0900_bin NOT NULL,
    channel VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
    title VARCHAR(160) NOT NULL,
    body TEXT NOT NULL,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    sent_at DATETIME(6),
    read_at DATETIME(6),
    CHECK (status IN ('PENDING', 'SENT', 'FAILED'))
) ENGINE=InnoDB COMMENT='Thông báo theo người nhận và ngữ cảnh';

CREATE TABLE feedback (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    court_id BIGINT,
    booking_id BIGINT,
    body TEXT NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Phản hồi về sân hoặc lượt đặt';

CREATE TABLE support_tickets (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    opened_by BIGINT NOT NULL,
    assigned_to BIGINT,
    facility_id BIGINT,
    booking_id BIGINT,
    subject VARCHAR(160) NOT NULL,
    description TEXT NOT NULL,
    attachment_ref TEXT,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'OPEN',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    closed_at DATETIME(6),
    CHECK (status IN ('OPEN', 'IN_PROGRESS', 'CLOSED'))
) ENGINE=InnoDB COMMENT='Phiếu hỗ trợ khách hàng';

CREATE TABLE support_messages (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    ticket_id BIGINT NOT NULL,
    author_id BIGINT NOT NULL,
    body TEXT NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))
) ENGINE=InnoDB COMMENT='Trao đổi trong phiếu hỗ trợ';

-- 08_report_exports.sql
-- 08 Báo cáo và thống kê
USE n01sport_dev;

CREATE TABLE report_exports (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    requested_by BIGINT NOT NULL,
    facility_id BIGINT,
    report_kind VARCHAR(30) COLLATE utf8mb4_0900_bin NOT NULL,
    filters JSON NOT NULL,
    format VARCHAR(8) COLLATE utf8mb4_0900_bin NOT NULL,
    file_ref TEXT,
    status VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'PENDING',
    created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    CHECK (format IN ('XLSX','PDF')),
    CHECK (status <> 'COMPLETED' OR file_ref IS NOT NULL),
    CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED'))
) ENGINE=InnoDB COMMENT='Nhật ký xuất báo cáo Excel hoặc PDF';

-- 09_administration.sql
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

-- 10_facilities.sql
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

-- 11_keys_and_constraints.sql
-- Khóa ngoại, chỉ mục lịch và duy nhất có điều kiện
USE n01sport_dev;

CREATE INDEX bookings_court_schedule ON bookings (court_id, start_at, end_at);
CREATE INDEX bookings_status_expiry ON bookings (status, expires_at);
CREATE INDEX bookings_customer_history ON bookings (customer_id, created_at DESC);
CREATE INDEX booking_status_history_timeline ON booking_status_history (booking_id, changed_at, id);
CREATE INDEX audit_logs_entity_timeline ON audit_logs (entity_type, entity_key, created_at, id);
CREATE UNIQUE INDEX sales_payments_one_success ON sales_payments ((CASE WHEN status = 'SUCCEEDED' THEN order_id END));
CREATE UNIQUE INDEX promotion_usages_one_live_voucher ON promotion_usages ((CASE WHEN status IN ('HELD','USED') THEN redemption_id END));
CREATE UNIQUE INDEX point_transactions_one_earn ON point_transactions ((CASE WHEN kind = 'EARN' THEN booking_id END));
CREATE UNIQUE INDEX point_transactions_one_reversal ON point_transactions ((CASE WHEN kind = 'REVERSAL' THEN booking_id END));
CREATE UNIQUE INDEX point_transactions_one_redemption ON point_transactions ((CASE WHEN kind = 'REDEEM' THEN redemption_id END));
CREATE UNIQUE INDEX user_role_grants_one_open ON user_role_grants ((CASE WHEN revoked_at IS NULL THEN user_id END), role_id, (CASE WHEN revoked_at IS NULL THEN COALESCE(facility_id,0) END));

ALTER TABLE auth_sessions ADD CONSTRAINT fk_auth_sessions_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE auth_challenges ADD CONSTRAINT fk_auth_challenges_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE courts ADD CONSTRAINT fk_courts_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE courts ADD CONSTRAINT fk_courts_sport_type_id FOREIGN KEY (sport_type_id) REFERENCES sport_types (id);
ALTER TABLE court_images ADD CONSTRAINT fk_court_images_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE court_hours ADD CONSTRAINT fk_court_hours_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE court_blocks ADD CONSTRAINT fk_court_blocks_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE court_blocks ADD CONSTRAINT fk_court_blocks_created_by FOREIGN KEY (created_by) REFERENCES users (id);
ALTER TABLE court_blocks ADD CONSTRAINT fk_court_blocks_maintenance_id FOREIGN KEY (maintenance_id) REFERENCES maintenance_requests (id);
ALTER TABLE court_prices ADD CONSTRAINT fk_court_prices_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE court_prices ADD CONSTRAINT fk_court_prices_supersedes_id FOREIGN KEY (supersedes_id) REFERENCES court_prices (id);
ALTER TABLE court_prices ADD CONSTRAINT fk_court_prices_proposed_by FOREIGN KEY (proposed_by) REFERENCES users (id);
ALTER TABLE court_prices ADD CONSTRAINT fk_court_prices_decided_by FOREIGN KEY (decided_by) REFERENCES users (id);
ALTER TABLE court_amenities ADD CONSTRAINT fk_court_amenities_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE court_amenities ADD CONSTRAINT fk_court_amenities_amenity_id FOREIGN KEY (amenity_id) REFERENCES amenities (id);
ALTER TABLE customers ADD CONSTRAINT fk_customers_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE customers ADD CONSTRAINT fk_customers_home_facility_id FOREIGN KEY (home_facility_id) REFERENCES facilities (id);
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_customer_id FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_series_id FOREIGN KEY (series_id) REFERENCES booking_series (id);
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_handled_by FOREIGN KEY (handled_by) REFERENCES users (id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE coach_profiles ADD CONSTRAINT fk_coach_profiles_customer_id FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE coach_profiles ADD CONSTRAINT fk_coach_profiles_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE coach_profiles ADD CONSTRAINT fk_coach_profiles_reviewed_by FOREIGN KEY (reviewed_by) REFERENCES users (id);
ALTER TABLE booking_series ADD CONSTRAINT fk_booking_series_coach_profile_id FOREIGN KEY (coach_profile_id) REFERENCES coach_profiles (id);
ALTER TABLE booking_series ADD CONSTRAINT fk_booking_series_preferred_court_id FOREIGN KEY (preferred_court_id) REFERENCES courts (id);
ALTER TABLE payment_events ADD CONSTRAINT fk_payment_events_payment_id FOREIGN KEY (payment_id) REFERENCES payments (id);
ALTER TABLE booking_price_lines ADD CONSTRAINT fk_booking_price_lines_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE booking_price_lines ADD CONSTRAINT fk_booking_price_lines_court_price_id FOREIGN KEY (court_price_id) REFERENCES court_prices (id);
ALTER TABLE booking_status_history ADD CONSTRAINT fk_booking_status_history_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE booking_status_history ADD CONSTRAINT fk_booking_status_history_changed_by FOREIGN KEY (changed_by) REFERENCES users (id);
ALTER TABLE refund_requests ADD CONSTRAINT fk_refund_requests_payment_id FOREIGN KEY (payment_id) REFERENCES payments (id);
ALTER TABLE refund_requests ADD CONSTRAINT fk_refund_requests_requested_by FOREIGN KEY (requested_by) REFERENCES users (id);
ALTER TABLE refund_requests ADD CONSTRAINT fk_refund_requests_decided_by FOREIGN KEY (decided_by) REFERENCES users (id);
ALTER TABLE refunds ADD CONSTRAINT fk_refunds_request_id FOREIGN KEY (request_id) REFERENCES refund_requests (id);
ALTER TABLE facility_inventory ADD CONSTRAINT fk_facility_inventory_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE facility_inventory ADD CONSTRAINT fk_facility_inventory_product_id FOREIGN KEY (product_id) REFERENCES products (id);
ALTER TABLE sales_orders ADD CONSTRAINT fk_sales_orders_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE sales_orders ADD CONSTRAINT fk_sales_orders_customer_id FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE sales_orders ADD CONSTRAINT fk_sales_orders_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE sales_orders ADD CONSTRAINT fk_sales_orders_created_by FOREIGN KEY (created_by) REFERENCES users (id);
ALTER TABLE sales_order_lines ADD CONSTRAINT fk_sales_order_lines_order_id FOREIGN KEY (order_id) REFERENCES sales_orders (id);
ALTER TABLE sales_order_lines ADD CONSTRAINT fk_sales_order_lines_inventory_id FOREIGN KEY (inventory_id) REFERENCES facility_inventory (id);
ALTER TABLE sales_payments ADD CONSTRAINT fk_sales_payments_order_id FOREIGN KEY (order_id) REFERENCES sales_orders (id);
ALTER TABLE sales_payments ADD CONSTRAINT fk_sales_payments_recorded_by FOREIGN KEY (recorded_by) REFERENCES users (id);
ALTER TABLE equipment_items ADD CONSTRAINT fk_equipment_items_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE equipment_items ADD CONSTRAINT fk_equipment_items_equipment_type_id FOREIGN KEY (equipment_type_id) REFERENCES equipment_types (id);
ALTER TABLE rental_orders ADD CONSTRAINT fk_rental_orders_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE rental_orders ADD CONSTRAINT fk_rental_orders_customer_id FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE rental_orders ADD CONSTRAINT fk_rental_orders_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE rental_orders ADD CONSTRAINT fk_rental_orders_created_by FOREIGN KEY (created_by) REFERENCES users (id);
ALTER TABLE rental_order_lines ADD CONSTRAINT fk_rental_order_lines_rental_id FOREIGN KEY (rental_id) REFERENCES rental_orders (id);
ALTER TABLE rental_order_lines ADD CONSTRAINT fk_rental_order_lines_equipment_id FOREIGN KEY (equipment_id) REFERENCES equipment_items (id);
ALTER TABLE rental_transactions ADD CONSTRAINT fk_rental_transactions_rental_id FOREIGN KEY (rental_id) REFERENCES rental_orders (id);
ALTER TABLE rental_transactions ADD CONSTRAINT fk_rental_transactions_recorded_by FOREIGN KEY (recorded_by) REFERENCES users (id);
ALTER TABLE technical_tickets ADD CONSTRAINT fk_technical_tickets_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE technical_tickets ADD CONSTRAINT fk_technical_tickets_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE technical_tickets ADD CONSTRAINT fk_technical_tickets_equipment_id FOREIGN KEY (equipment_id) REFERENCES equipment_items (id);
ALTER TABLE technical_tickets ADD CONSTRAINT fk_technical_tickets_reported_by FOREIGN KEY (reported_by) REFERENCES users (id);
ALTER TABLE technical_tickets ADD CONSTRAINT fk_technical_tickets_resolved_by FOREIGN KEY (resolved_by) REFERENCES users (id);
ALTER TABLE employees ADD CONSTRAINT fk_employees_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE facility_staff_assignments ADD CONSTRAINT fk_facility_staff_assignments_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE facility_staff_assignments ADD CONSTRAINT fk_facility_staff_assignments_employee_id FOREIGN KEY (employee_id) REFERENCES employees (id);
ALTER TABLE facility_staff_assignments ADD CONSTRAINT fk_facility_staff_assignments_assigned_by FOREIGN KEY (assigned_by) REFERENCES users (id);
ALTER TABLE staff_shifts ADD CONSTRAINT fk_staff_shifts_staff_assignment_id FOREIGN KEY (staff_assignment_id) REFERENCES facility_staff_assignments (id);
ALTER TABLE account_access_requests ADD CONSTRAINT fk_account_access_requests_staff_assignment_id FOREIGN KEY (staff_assignment_id) REFERENCES facility_staff_assignments (id);
ALTER TABLE account_access_requests ADD CONSTRAINT fk_account_access_requests_requested_by FOREIGN KEY (requested_by) REFERENCES users (id);
ALTER TABLE account_access_requests ADD CONSTRAINT fk_account_access_requests_resolved_by FOREIGN KEY (resolved_by) REFERENCES users (id);
ALTER TABLE technical_assignments ADD CONSTRAINT fk_technical_assignments_ticket_id FOREIGN KEY (ticket_id) REFERENCES technical_tickets (id);
ALTER TABLE technical_assignments ADD CONSTRAINT fk_technical_assignments_staff_assignment_id FOREIGN KEY (staff_assignment_id) REFERENCES facility_staff_assignments (id);
ALTER TABLE technical_assignments ADD CONSTRAINT fk_technical_assignments_assigned_by FOREIGN KEY (assigned_by) REFERENCES users (id);
ALTER TABLE technical_updates ADD CONSTRAINT fk_technical_updates_assignment_id FOREIGN KEY (assignment_id) REFERENCES technical_assignments (id);
ALTER TABLE maintenance_requests ADD CONSTRAINT fk_maintenance_requests_assignment_id FOREIGN KEY (assignment_id) REFERENCES technical_assignments (id);
ALTER TABLE maintenance_requests ADD CONSTRAINT fk_maintenance_requests_decided_by FOREIGN KEY (decided_by) REFERENCES users (id);
ALTER TABLE cleaning_tasks ADD CONSTRAINT fk_cleaning_tasks_shift_id FOREIGN KEY (shift_id) REFERENCES staff_shifts (id);
ALTER TABLE cleaning_tasks ADD CONSTRAINT fk_cleaning_tasks_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE cleaning_tasks ADD CONSTRAINT fk_cleaning_tasks_assigned_by FOREIGN KEY (assigned_by) REFERENCES users (id);
ALTER TABLE promotions ADD CONSTRAINT fk_promotions_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE promotion_versions ADD CONSTRAINT fk_promotion_versions_promotion_id FOREIGN KEY (promotion_id) REFERENCES promotions (id);
ALTER TABLE promotion_versions ADD CONSTRAINT fk_promotion_versions_proposed_by FOREIGN KEY (proposed_by) REFERENCES users (id);
ALTER TABLE promotion_versions ADD CONSTRAINT fk_promotion_versions_decided_by FOREIGN KEY (decided_by) REFERENCES users (id);
ALTER TABLE promotion_usages ADD CONSTRAINT fk_promotion_usages_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE promotion_usages ADD CONSTRAINT fk_promotion_usages_promotion_version_id FOREIGN KEY (promotion_version_id) REFERENCES promotion_versions (id);
ALTER TABLE promotion_usages ADD CONSTRAINT fk_promotion_usages_redemption_id FOREIGN KEY (redemption_id) REFERENCES reward_redemptions (id);
ALTER TABLE loyalty_accounts ADD CONSTRAINT fk_loyalty_accounts_customer_id FOREIGN KEY (customer_id) REFERENCES customers (id);
ALTER TABLE loyalty_accounts ADD CONSTRAINT fk_loyalty_accounts_tier_id FOREIGN KEY (tier_id) REFERENCES loyalty_tiers (id);
ALTER TABLE point_transactions ADD CONSTRAINT fk_point_transactions_loyalty_account_id FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_accounts (id);
ALTER TABLE point_transactions ADD CONSTRAINT fk_point_transactions_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE point_transactions ADD CONSTRAINT fk_point_transactions_redemption_id FOREIGN KEY (redemption_id) REFERENCES reward_redemptions (id);
ALTER TABLE point_transactions ADD CONSTRAINT fk_point_transactions_rule_id FOREIGN KEY (rule_id) REFERENCES loyalty_rules (id);
ALTER TABLE loyalty_rules ADD CONSTRAINT fk_loyalty_rules_configured_by FOREIGN KEY (configured_by) REFERENCES users (id);
ALTER TABLE reward_offers ADD CONSTRAINT fk_reward_offers_promotion_id FOREIGN KEY (promotion_id) REFERENCES promotions (id);
ALTER TABLE reward_redemptions ADD CONSTRAINT fk_reward_redemptions_loyalty_account_id FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_accounts (id);
ALTER TABLE reward_redemptions ADD CONSTRAINT fk_reward_redemptions_reward_offer_id FOREIGN KEY (reward_offer_id) REFERENCES reward_offers (id);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_payment_id FOREIGN KEY (payment_id) REFERENCES payments (id);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_court_block_id FOREIGN KEY (court_block_id) REFERENCES court_blocks (id);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE feedback ADD CONSTRAINT fk_feedback_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE feedback ADD CONSTRAINT fk_feedback_court_id FOREIGN KEY (court_id) REFERENCES courts (id);
ALTER TABLE feedback ADD CONSTRAINT fk_feedback_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE support_tickets ADD CONSTRAINT fk_support_tickets_opened_by FOREIGN KEY (opened_by) REFERENCES users (id);
ALTER TABLE support_tickets ADD CONSTRAINT fk_support_tickets_assigned_to FOREIGN KEY (assigned_to) REFERENCES users (id);
ALTER TABLE support_tickets ADD CONSTRAINT fk_support_tickets_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE support_tickets ADD CONSTRAINT fk_support_tickets_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id);
ALTER TABLE support_messages ADD CONSTRAINT fk_support_messages_ticket_id FOREIGN KEY (ticket_id) REFERENCES support_tickets (id);
ALTER TABLE support_messages ADD CONSTRAINT fk_support_messages_author_id FOREIGN KEY (author_id) REFERENCES users (id);
ALTER TABLE report_exports ADD CONSTRAINT fk_report_exports_requested_by FOREIGN KEY (requested_by) REFERENCES users (id);
ALTER TABLE report_exports ADD CONSTRAINT fk_report_exports_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE role_permissions ADD CONSTRAINT fk_role_permissions_role_id FOREIGN KEY (role_id) REFERENCES roles (id);
ALTER TABLE role_permissions ADD CONSTRAINT fk_role_permissions_permission_id FOREIGN KEY (permission_id) REFERENCES permissions (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_role_id FOREIGN KEY (role_id) REFERENCES roles (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_coach_profile_id FOREIGN KEY (coach_profile_id) REFERENCES coach_profiles (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_manager_assignment_id FOREIGN KEY (manager_assignment_id) REFERENCES facility_manager_assignments (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_staff_assignment_id FOREIGN KEY (staff_assignment_id) REFERENCES facility_staff_assignments (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_granted_by FOREIGN KEY (granted_by) REFERENCES users (id);
ALTER TABLE user_role_grants ADD CONSTRAINT fk_user_role_grants_revoked_by FOREIGN KEY (revoked_by) REFERENCES users (id);
ALTER TABLE system_settings ADD CONSTRAINT fk_system_settings_updated_by FOREIGN KEY (updated_by) REFERENCES users (id);
ALTER TABLE backup_jobs ADD CONSTRAINT fk_backup_jobs_source_backup_id FOREIGN KEY (source_backup_id) REFERENCES backup_jobs (id);
ALTER TABLE backup_jobs ADD CONSTRAINT fk_backup_jobs_requested_by FOREIGN KEY (requested_by) REFERENCES users (id);
ALTER TABLE audit_logs ADD CONSTRAINT fk_audit_logs_actor_id FOREIGN KEY (actor_id) REFERENCES users (id);
ALTER TABLE audit_logs ADD CONSTRAINT fk_audit_logs_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE login_events ADD CONSTRAINT fk_login_events_user_id FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE facilities ADD CONSTRAINT fk_facilities_created_by FOREIGN KEY (created_by) REFERENCES users (id);
ALTER TABLE facility_suspensions ADD CONSTRAINT fk_facility_suspensions_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE facility_suspensions ADD CONSTRAINT fk_facility_suspensions_created_by FOREIGN KEY (created_by) REFERENCES users (id);
ALTER TABLE facility_manager_assignments ADD CONSTRAINT fk_facility_manager_assignments_facility_id FOREIGN KEY (facility_id) REFERENCES facilities (id);
ALTER TABLE facility_manager_assignments ADD CONSTRAINT fk_facility_manager_assignments_employee_id FOREIGN KEY (employee_id) REFERENCES employees (id);
ALTER TABLE facility_manager_assignments ADD CONSTRAINT fk_facility_manager_assignments_appointed_by FOREIGN KEY (appointed_by) REFERENCES users (id);

-- 12_booking_workflows.sql
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

-- 13_operational_workflows.sql
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

-- 14_reporting_views.sql
USE n01sport_dev;

-- Dòng ghi sổ theo giờ Việt Nam. Các khoản thu đang đối soát được theo dõi ở payments.
CREATE SQL SECURITY INVOKER VIEW vw_revenue
(facility_id,posting_date,category,source_key,signed_amount) AS
WITH recognized_court_payments AS (
    SELECT p.id,p.amount,p.received_at,c.facility_id
    FROM payments p JOIN bookings b ON b.id=p.booking_id JOIN courts c ON c.id=b.court_id
    WHERE p.status='SUCCEEDED' AND p.received_at<b.expires_at
      AND EXISTS (SELECT 1 FROM booking_status_history h WHERE h.booking_id=b.id AND h.to_status='CONFIRMED')
)
SELECT facility_id,DATE(received_at+INTERVAL 7 HOUR),'COURT',CONCAT('payment:',id),amount
FROM recognized_court_payments
UNION ALL
SELECT p.facility_id,DATE(r.settled_at+INTERVAL 7 HOUR),'COURT',CONCAT('refund:',r.id),-r.amount
FROM refunds r JOIN refund_requests q ON q.id=r.request_id AND q.status='APPROVED'
JOIN recognized_court_payments p ON p.id=q.payment_id WHERE r.status='SUCCEEDED'
UNION ALL
SELECT o.facility_id,DATE(p.paid_at+INTERVAL 7 HOUR),'SALE',CONCAT('sale:',p.id),p.amount
FROM sales_payments p JOIN sales_orders o ON o.id=p.order_id
WHERE p.status='SUCCEEDED' AND o.status='PAID'
UNION ALL
SELECT o.facility_id,DATE(r.posted_at+INTERVAL 7 HOUR),r.kind,CONCAT('rental:',r.id),r.amount
FROM rental_transactions r JOIN rental_orders o ON o.id=r.rental_id
WHERE r.status='SUCCEEDED' AND r.kind IN ('RENT','DAMAGE_COMPENSATION');

-- Các khoảng bị chặn được gom hợp trước khi trừ, để bảo trì và tạm ngừng không bị trừ hai lần.
CREATE SQL SECURITY INVOKER VIEW vw_court_utilization
(court_id,usage_date,used_minutes,available_minutes,booking_count) AS
WITH RECURSIVE
report_limit AS (
    SELECT DATE(UTC_TIMESTAMP()+INTERVAL 7 HOUR) AS last_day
), source_dates AS (
    SELECT MIN(valid_from) AS first_day FROM court_hours
    UNION ALL SELECT DATE(MIN(start_at)+INTERVAL 7 HOUR) FROM bookings
), months (first_of_month) AS (
    SELECT CAST(DATE_FORMAT(MIN(first_day),'%Y-%m-01') AS DATE) FROM source_dates
    UNION ALL
    SELECT DATE_ADD(first_of_month,INTERVAL 1 MONTH) FROM months,report_limit
    WHERE DATE_ADD(first_of_month,INTERVAL 1 MONTH)<=last_day
), digits (n) AS (
    SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
), day_offsets AS (
    SELECT a.n+10*b.n AS n FROM digits a CROSS JOIN digits b WHERE a.n+10*b.n<=30
), candidate_days AS (
    SELECT DATE_ADD(m.first_of_month,INTERVAL d.n DAY) AS day
    FROM months m CROSS JOIN day_offsets d
    WHERE d.n<DAY(LAST_DAY(m.first_of_month))
), report_days AS (
    SELECT day,CAST(day AS DATETIME)-INTERVAL 7 HOUR AS begin_utc,
           CAST(day AS DATETIME)+INTERVAL 17 HOUR AS end_utc
    FROM candidate_days,report_limit WHERE day<=last_day
), open_hours AS (
    SELECT h.id,h.court_id,c.facility_id,d.day,
           TIMESTAMP(d.day,h.opens_at)-INTERVAL 7 HOUR AS opens_utc,
           TIMESTAMP(d.day,h.closes_at)-INTERVAL 7 HOUR AS closes_utc
    FROM court_hours h JOIN courts c ON c.id=h.court_id JOIN report_days d
      ON d.day>=h.valid_from AND (h.valid_to IS NULL OR d.day<h.valid_to)
      AND WEEKDAY(d.day)+1=h.weekday
), status_events AS (
    SELECT entity_type,entity_key,created_at AS starts,
           LEAD(created_at) OVER(PARTITION BY entity_type,entity_key ORDER BY created_at,id) AS ends,
           ROW_NUMBER() OVER(PARTITION BY entity_type,entity_key ORDER BY created_at,id) AS ordinal,
           JSON_UNQUOTE(JSON_EXTRACT(details,'$.status')) AS state
    FROM audit_logs WHERE action='AVAILABILITY_STATUS' AND entity_type IN ('courts','facilities')
), unavailable AS (
    SELECT court_id,NULL AS facility_id,starts_at AS starts,
           LEAST(ends_at,COALESCE(released_at,ends_at)) AS ends
    FROM court_blocks
    UNION ALL SELECT NULL,facility_id,starts_at,ends_at FROM facility_suspensions
    UNION ALL
    SELECT CASE WHEN entity_type='courts' THEN CAST(entity_key AS UNSIGNED) END,
           CASE WHEN entity_type='facilities' THEN CAST(entity_key AS UNSIGNED) END,starts,ends
    FROM status_events WHERE state<>'ACTIVE'
    UNION ALL
    SELECT CASE WHEN entity_type='courts' THEN CAST(entity_key AS UNSIGNED) END,
           CASE WHEN entity_type='facilities' THEN CAST(entity_key AS UNSIGNED) END,
           CAST('1000-01-01' AS DATETIME),starts
    FROM status_events WHERE ordinal=1
), clipped_outages AS (
    SELECT h.id,h.day,GREATEST(h.opens_utc,u.starts) AS starts,
           LEAST(h.closes_utc,COALESCE(u.ends,h.closes_utc)) AS ends
    FROM open_hours h JOIN unavailable u ON (u.court_id=h.court_id OR u.facility_id=h.facility_id)
      AND u.starts<h.closes_utc AND (u.ends IS NULL OR h.opens_utc<u.ends)
      AND (u.ends IS NULL OR u.starts<u.ends)
), previous_end AS (
    SELECT id,day,starts,ends,MAX(ends) OVER(PARTITION BY id,day ORDER BY starts,ends
             ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS previous_max
    FROM clipped_outages
), outage_duration AS (
    SELECT id,day,SUM(GREATEST(0,TIMESTAMPDIFF(MICROSECOND,
            GREATEST(starts,COALESCE(previous_max,starts)),ends))) AS micros
    FROM previous_end GROUP BY id,day
), capacity AS (
    SELECT h.court_id,h.day,FLOOR(SUM(TIMESTAMPDIFF(MICROSECOND,h.opens_utc,h.closes_utc)
            -COALESCE(u.micros,0))/60000000) AS mins
    FROM open_hours h LEFT JOIN outage_duration u ON u.id=h.id AND u.day=h.day
    GROUP BY h.court_id,h.day
), actual AS (
    SELECT b.court_id,d.day,FLOOR(SUM(CASE WHEN b.status='COMPLETED'
          THEN TIMESTAMPDIFF(MICROSECOND,GREATEST(b.start_at,d.begin_utc),LEAST(b.end_at,d.end_utc))
          ELSE 0 END)/60000000) AS mins,
          SUM(b.start_at>=d.begin_utc AND b.start_at<d.end_utc) AS bookings
    FROM bookings b JOIN report_days d ON b.start_at<d.end_utc AND d.begin_utc<b.end_at
    WHERE b.status IN ('CONFIRMED','CHECKED_IN','COMPLETED','NO_SHOW')
    GROUP BY b.court_id,d.day
), result_days AS (
    SELECT court_id,day FROM capacity
    UNION SELECT court_id,day FROM actual
)
SELECT d.court_id,d.day,COALESCE(a.mins,0),COALESCE(c.mins,0),COALESCE(a.bookings,0)
FROM result_days d LEFT JOIN actual a ON a.court_id=d.court_id AND a.day=d.day
LEFT JOIN capacity c ON c.court_id=d.court_id AND c.day=d.day;

CREATE SQL SECURITY INVOKER VIEW vw_customer_metrics
(customer_id,created_at,facility_id,booking_count,court_spend,points_balance,tier_code) AS
WITH booking_counts AS (
    SELECT customer_id,COUNT(*) AS total FROM bookings
    WHERE status IN ('CONFIRMED','CHECKED_IN','COMPLETED','NO_SHOW') GROUP BY customer_id
), customer_transaction_keys AS (
    SELECT b.customer_id,CONCAT('payment:',p.id) AS source_key FROM payments p JOIN bookings b ON b.id=p.booking_id
    UNION ALL
    SELECT b.customer_id,CONCAT('refund:',r.id) FROM refunds r JOIN refund_requests q ON q.id=r.request_id
    JOIN payments p ON p.id=q.payment_id JOIN bookings b ON b.id=p.booking_id
), customer_spend AS (
    SELECT k.customer_id,SUM(v.signed_amount) AS net
    FROM vw_revenue v JOIN customer_transaction_keys k ON k.source_key=v.source_key
    WHERE v.category='COURT' GROUP BY k.customer_id
)
SELECT c.id,c.created_at,c.home_facility_id,COALESCE(b.total,0),COALESCE(s.net,0),COALESCE(a.balance,0),t.code
FROM customers c
LEFT JOIN booking_counts b ON b.customer_id=c.id LEFT JOIN customer_spend s ON s.customer_id=c.id
LEFT JOIN loyalty_accounts a ON a.customer_id=c.id LEFT JOIN loyalty_tiers t ON t.id=a.tier_id;

-- 15_reference_data.sql
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
