# Hướng dẫn database N01SPORT

Nhóm dùng MySQL 8.0.46, database `n01sport_dev`, InnoDB và utf8mb4. Bộ cài gồm 66 bảng, 133 khóa ngoại, 3 view, 14 procedure, 1 function và 51 trigger. Thành viên mới làm theo thứ tự cài cấu trúc, nạp dữ liệu mẫu, tạo quyền backend và chạy test. Máy đã cài đủ bắt đầu từ dữ liệu mẫu hoặc cấu hình kết nối.

## 1 Các tệp cần biết

| Tệp hoặc thư mục | Mục đích |
|---|---|
| install.sql | Cài toàn bộ cấu trúc. Chạy một lần trên server chưa có database n01sport_dev. |
| migrations/00–15 | SQL theo phân hệ và phần dùng chung. Chạy theo thứ tự nếu chọn cách cài từng migration. |
| seeds/001_demo.sql | Tạo cơ sở, sân, lịch, giá, khách và hàng mẫu. Có thể chạy lại để bổ sung phần còn thiếu. |
| app_role.sql | Tạo role MySQL n01sport_dev_app dành cho backend. |
| verify.sql | Kiểm tra số bảng, view, FK và xem các liên kết của bookings. |
| tests/run.ps1 | Tạo database thử riêng và chạy smoke.sql. |
| tests/smoke.sql | Các bài thử SQL, kết thúc có PASS khi đạt. |
| docs/Huong_dan_database_N01SPORT.docx | Giải thích từng migration, luồng dữ liệu và cách viết backend. |

install.sql tổng hợp nội dung migration 00–15. Chọn một cách cài. Mỗi thành viên có database local riêng, được dựng từ cùng mã SQL trong repo. Dữ liệu thực tế được MySQL Server lưu trữ. Workbench giúp chạy SQL và xem dữ liệu.

## 2 Cài cấu trúc bằng Workbench

1. Kết nối MySQL Server bằng tài khoản cài đặt, ví dụ root.
2. Chọn File > Open SQL Script và mở `database/install.sql` từ repo đã pull.
3. Chạy toàn bộ một lần. Nếu có lỗi, xem lỗi đầu tiên trong Output trước khi tiếp tục.
4. Refresh SCHEMAS và chọn `n01sport_dev`.
5. Mở `database/verify.sql`. Chạy `USE n01sport_dev;` trước các truy vấn nếu chưa chọn database.

Kết quả cần có 66 bảng, 3 view, 133 khóa ngoại. Kiểm tra routine, trigger và vai trò bằng SQL sau.

```sql
USE n01sport_dev;
SELECT routine_type, COUNT(*)
FROM information_schema.routines
WHERE routine_schema = DATABASE()
GROUP BY routine_type;
SELECT COUNT(*) AS trigger_count
FROM information_schema.triggers
WHERE trigger_schema = DATABASE();
SELECT code, name FROM roles ORDER BY code;
```

Các số tương ứng là 14 procedure, 1 function, 51 trigger và 6 vai trò. Có thể cài từ PowerShell tại thư mục gốc dự án.

```powershell
mysql -h 127.0.0.1 -P 3306 -u root -p --default-character-set=utf8mb4 -e "source database/install.sql"
```

Chỉnh host, cổng và tài khoản theo máy. Nhập mật khẩu khi được hỏi. Nếu mysql.exe chưa nằm trong PATH, dùng đường dẫn đầy đủ tới file trong thư mục bin của MySQL. MySQL có các câu DDL tự commit, nên khi cài lỗi giữa chừng cần kiểm tra phần đã tạo trước khi chạy tiếp. [Tài liệu MySQL](https://dev.mysql.com/doc/refman/8.0/en/implicit-commit.html)

## 3 Nạp và xem dữ liệu mẫu

Mở `database/seeds/001_demo.sql` và chạy bằng tài khoản cài đặt. Kết quả cuối cần có `seed_result = OK`. Có thể chạy lại để tìm dữ liệu đã có và bổ sung phần thiếu. Nếu còn transaction từ lần seed cũ bị lỗi, xử lý hoặc rollback transaction đó trước khi chạy.

```sql
USE n01sport_dev;
SELECT id, email, status FROM users;
SELECT id, code, name FROM facilities;
SELECT id, facility_id, code, name FROM courts;
SELECT id, user_id, full_name FROM customers;
```

Seed dùng email, mã và khóa liên kết để nhận diện dữ liệu mẫu. Lịch và giá còn hiệu lực được dùng lại. Tồn kho đã thay đổi trong quá trình thử giữ giá trị hiện có. Seed chạy trong transaction và rollback khi lỗi. Tài khoản mẫu chứa băm mật khẩu giả. Để thử đăng nhập web, tạo tài khoản qua backend với thuật toán băm của dự án.

## 4 Tạo tài khoản backend

Chạy `database/app_role.sql` bằng tài khoản quản trị. Sau đó tạo tài khoản dịch vụ với mật khẩu riêng và gán role như dưới đây. Host của tài khoản cần khớp nơi backend kết nối.

```sql
CREATE USER 'n01sport_local'@'localhost'
IDENTIFIED BY '<mat khau rieng cua ban>';
GRANT 'n01sport_dev_app' TO 'n01sport_local'@'localhost';
SET DEFAULT ROLE 'n01sport_dev_app'
TO 'n01sport_local'@'localhost';
```

Ví dụ biến môi trường để nhóm thống nhất với driver.

```dotenv
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=n01sport_dev
DB_USER=n01sport_local
DB_PASSWORD=
```

Đặt mật khẩu thực trong .env local đã được Git bỏ qua. Repo chia sẻ .env.example với tên biến và giá trị minh họa. Backend cần driver MySQL, connection pool và cơ chế đọc biến môi trường. Package.json hiện tại mới là khung dự án.

Role MySQL trên cấp quyền kết nối của backend. Các vai trò CUSTOMER, COACH, OWNER, FACILITY_MANAGER, STAFF và SYSTEM_ADMIN trong bảng roles dùng để phân quyền người dùng web. Backend xác thực phiên, quyền sở hữu booking và phạm vi cơ sở trước mọi thao tác. View báo cáo cung cấp dữ liệu toàn database nên API phải lọc theo phạm vi được phép.

## 5 Chạy bài kiểm thử

Mở PowerShell tại thư mục gốc repo.

```powershell
.\database\tests\run.ps1 -User root -Port 3306
```

Nếu cần chỉ định vị trí MySQL client.

```powershell
.\database\tests\run.ps1 -MysqlExe "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
```

Nhập mật khẩu khi được hỏi. Script tạo database có tiền tố n01sport_test_, cài cấu trúc rồi chạy smoke.sql. Kết quả thành công có PASS và tên database thử. Database thử được giữ lại để xem dữ liệu.

Bài test kiểm tra cấu trúc, quyền theo cơ sở, đặt trùng và liền kề, callback sai số tiền hoặc gửi lặp hoặc đến muộn, hủy, hoàn tiền, bán hàng, dụng cụ, khuyến mãi, tích và đảo điểm. Cần kiểm thử API, giao diện, đăng nhập và cổng thanh toán sandbox khi backend được viết.

## 6 Quy tắc khi viết backend

Luồng chính là giao diện gọi API, API xác thực và kiểm tra đầu vào, service gọi SQL bằng tham số rồi trả dữ liệu cho giao diện. Các thủ tục có transaction riêng được gọi trên connection autocommit, bên ngoài transaction do ứng dụng mở.

| Chức năng | Cách gọi |
|---|---|
| Giữ sân | hold_booking(code, customer_id, court_id, series_id, start_utc, end_utc, promotion_version_id, redemption_id). Dùng NULL cho lựa chọn không có. SQL khóa theo sân, tính giá và tạo giữ chỗ 15 phút. |
| Tạo QR | create_payment_request(booking_id, key, amount), gọi nhà cung cấp rồi lưu QR bằng attach_payment_gateway(payment_id, provider_ref, qr_payload). |
| Callback | Xác minh chữ ký cổng trước khi gọi record_payment_callback(payment_id, provider_ref, event_key, amount, success). |
| Vận hành booking | move_booking(booking_id, actor_id, status, reason). Lập lịch gọi expire_bookings() định kỳ. |
| Thu bán hàng | settle_sale_payment(order_id, actor_id, key, method, amount). Ghi thu và trừ tồn cùng transaction. |
| Hoàn ngoại lệ | submit_refund_request, decide_refund_request, create_refund_attempt, settle_refund_attempt. Backend gọi cổng hoàn tiền thực. |
| Điểm và quyền | redeem_loyalty_reward, grant_application_role, revoke_application_role. |

DATETIME(6) lưu UTC, lịch và giá sân dùng giờ Việt Nam UTC+07:00. Tiền theo VND dùng DECIMAL(14,0). Khoảng sân có dạng [bắt đầu, kết thúc) nên hai lượt liền kề được phép. Mã yêu cầu idempotency được giữ ổn định khi thử lại cùng thao tác. Provider reference và event key có tiền tố nhà cung cấp.

Ví dụ gọi từ service Node.js sau khi đã cấu hình pool và xác thực khách.

```javascript
const [resultSets] = await pool.execute(
  'CALL hold_booking(?, ?, ?, ?, ?, ?, ?, ?)',
  [bookingCode, customerId, courtId, null,
   startUtc, endUtc, null, null]
);
const booking = resultSets[0][0];
```

Đổi giờ đầu vào sang UTC. Ví dụ 10 giờ Việt Nam là 03 giờ UTC cùng ngày. Dùng ID khách lấy từ phiên đăng nhập. Database tính giá từ bảng giá đã duyệt và trả amount_due, expires_at để hiển thị.

## 7 Làm việc nhóm qua GitHub

Đưa thư mục database gồm SQL, seeds, tests, README và Word vào repo. Mỗi thành viên pull cùng phiên bản và cấu hình kết nối local.

```powershell
git status --short
git add database
git diff --cached --stat
git commit -m "Prepare N01SPORT MySQL database handoff"
```

Kiểm tra file đã stage trước khi commit. Push theo remote và nhánh nhóm đang dùng. Mật khẩu và .env thực được quản lý riêng từng môi trường.

Khi schema đã chia sẻ, tạo migration bổ sung từ số 16, cập nhật install.sql cho máy mới và chạy lại test trước khi merge. Máy đã cài chỉ áp dụng migration mới tương ứng. Thống nhất thay đổi tên cột với người làm API và cập nhật ERD.

## 8 Lỗi thường gặp

| Hiện tượng | Xử lý |
|---|---|
| Table users already exists | Chạy verify.sql và xem lỗi đầu tiên. Bộ cài mới yêu cầu database chưa tồn tại. |
| Duplicate demo.owner@example.invalid | Đóng tab seed cũ, mở lại seeds/001_demo.sql bản hiện tại rồi chạy. |
| Access denied | Kiểm tra host, cổng, user, mật khẩu và role MySQL. |
| Could not isolate the test database name | Dùng tests/run.ps1 cùng phiên bản với install.sql và mẫu n01sport_dev. |
| mysql.exe chưa được tìm thấy | Thêm PATH hoặc truyền -MysqlExe. |
| Ghi trực tiếp bookings bị từ chối | Service dùng thủ tục hold_booking hoặc move_booking theo nghiệp vụ. |

Số lượng đối tượng khớp xác nhận phần cấu trúc cơ bản. PASS xác nhận các tình huống SQL trong bài test. Việc chạy đúng web cần kiểm thử tích hợp backend, giao diện, tác vụ định kỳ và nhà cung cấp thanh toán.

ERD gốc còn một số nhãn PostgreSQL. Dùng kiểu vật lý trong migration MySQL làm chuẩn khi viết code. TIMESTAMPTZ chuyển thành DATETIME(6) theo UTC, JSONB thành JSON, NUMERIC thành DECIMAL và PK tự tăng dùng AUTO_INCREMENT.
