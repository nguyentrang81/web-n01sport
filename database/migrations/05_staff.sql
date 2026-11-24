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
