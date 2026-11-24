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
