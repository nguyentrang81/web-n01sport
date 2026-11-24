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
