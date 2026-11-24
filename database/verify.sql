-- Chọn database n01sport hoặc n01sport_test_* trong MySQL Workbench trước khi chạy.
-- Các câu lệnh dưới đây chỉ đọc danh mục hệ thống.
SELECT DATABASE() AS database_hien_tai, VERSION() AS mysql_version;

SELECT 'Bảng' AS doi_tuong, 66 AS mong_doi, COUNT(*) AS thuc_te
FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE'
UNION ALL
SELECT 'View', 3, COUNT(*) FROM information_schema.views WHERE table_schema=DATABASE()
UNION ALL
SELECT 'Khóa ngoại', 133, COUNT(*) FROM information_schema.referential_constraints
WHERE constraint_schema=DATABASE();

-- Đổi bookings thành tên bảng cần xem.
SELECT table_name AS bang_con, column_name AS cot_con,
       referenced_table_name AS bang_cha, referenced_column_name AS cot_cha,
       constraint_name
FROM information_schema.key_column_usage
WHERE table_schema=DATABASE() AND referenced_table_schema=DATABASE()
  AND (table_name='bookings' OR referenced_table_name='bookings')
ORDER BY bang_con, bang_cha, constraint_name, ordinal_position;
