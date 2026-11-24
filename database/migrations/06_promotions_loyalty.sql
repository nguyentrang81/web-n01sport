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
