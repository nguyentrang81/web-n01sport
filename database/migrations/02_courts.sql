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
