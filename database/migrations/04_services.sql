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
