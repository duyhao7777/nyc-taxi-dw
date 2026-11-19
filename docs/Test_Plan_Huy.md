# TEST PLAN – NYC Yellow Taxi DW, giai đoạn 2

## A. Phạm vi và nguyên tắc kiểm thử

Đối tượng kiểm thử là mô hình DDS hoàn chỉnh: tám bảng chiều (`dim_date`, `dim_time`, `dim_location`, `dim_vendor`, `dim_payment_type`, `dim_rate_code`, `dim_passenger_group`, `dim_distance_band`) và bảng sự kiện `fact_trip` với 11 khóa chiều cùng hai độ đo `trip_count`, `trip_duration`.

Ba bộ kiểm thử được dùng để đối soát:

| Bộ | File | Nội dung | Số kiểm tra |
|---|---|---|---:|
| Theo từng kỳ | `sql/05_tests/08_master_period_checks.sql` | Đối soát số dòng, tổng tiền, grain, khóa ngoại, lineage, metadata, lịch, tám chiều, toàn vẹn khóa chiều và độ đo | 16 / kỳ |
| Toàn hệ thống | `sql/05_tests/05_reconcile_checks.sql` | Đối soát số dòng và tổng tiền toàn kho, trạng thái batch, danh mục zone, tám chiều, khóa chiều | 8 |
| Hồi quy mã | `tests/test_master_etl.py` | Quy tắc chuyển đổi và mã lỗi kép | 2 test method |

Mã điều kiện kiểm thử được đánh số theo hai dải: **TC01–TC16** cho các điều kiện kiểm thử tích hợp bằng SQL (mục B và C) và **TC17–TC29** cho các test chức năng, hồi quy và các khác biệt thiết kế (mục D).

Quy ước: **PASS** = có minh chứng đạt; **PARTIAL** = đã kiểm tra một phần kỳ vọng; **NOT RUN** = chưa thực hiện; **GAP** = khác biệt với thiết kế GĐ1 chưa xử lý.

Môi trường kiểm thử chính thức của phiên này được dựng lại hoàn toàn ngày 18–19/11/2026: SQL Server `azure-sql-edge` trong Docker, Mage trong container `mageai/mageai`, dữ liệu nguồn tải lại từ TLC, nạp ba kỳ 2024-01, 2024-02, 2025-01.

## B. Kiểm tra SQL theo từng kỳ (SQL 08)

Đổi `DECLARE @k CHAR(7)` theo kỳ cần kiểm tra. Kết quả thực nghiệm 19/11/2026: **cả 16 điều kiện đều PASS ở cả ba kỳ (48/48 lượt)**.

| ID | Nội dung | Kết quả mong đợi | 2024-01 | 2024-02 | 2025-01 |
|---|---|---|:---:|:---:|:---:|
| TC01 | Danh mục zone | 265 mã, 1–265 | PASS | PASS | PASS |
| TC02 | Source → Staging | log đọc = hợp lệ + loại; loaded/rejected khớp bảng | PASS | PASS | PASS |
| TC03 | Staging → bảng sự kiện | số dòng bằng nhau | PASS | PASS | PASS |
| TC04 | Tổng doanh thu | SUM(total_amount) khớp đến cent | PASS | PASS | PASS |
| TC05 | Grain bảng sự kiện | Không trùng `stg_trip_id` trong kỳ | PASS | PASS | PASS |
| TC06 | Khóa ngoại và lineage | Không orphan date/location/stg | PASS | PASS | PASS |
| TC07 | Chuyến hợp lệ theo mã hiện hành | Không còn bản ghi vi phạm quy tắc loại | PASS | PASS | PASS |
| TC08 | Lý do loại | Không rỗng | PASS | PASS | PASS |
| TC09 | Metadata | 2 control Success tham chiếu batch Success cùng kỳ | PASS | PASS | PASS |
| TC10 | Truy vết nguồn | `source_row_number` không trùng hoặc NULL giữa hợp lệ và loại | PASS | PASS | PASS |
| TC11 | Tổng tiền NULL | 0 dòng | PASS | PASS | PASS |
| TC12 | Lịch | Đủ ngày trong tháng | PASS | PASS | PASS |
| TC13 | Mô hình tám chiều | Cả tám bảng chiều đủ dữ liệu theo ngưỡng thiết kế giai đoạn 1 | PASS | PASS | PASS |
| TC14 | Toàn vẹn khóa chiều | Không dòng sự kiện nào thiếu 11 khóa chiều hoặc sai độ đo | PASS | PASS | PASS |
| TC15 | Độ đo của bảng sự kiện | `trip_count` bằng 1, `trip_duration` khớp thời gian đón–trả | PASS | PASS | PASS |
| TC16 | Doanh thu đi qua chiều | Tổng doanh thu nối qua các chiều bằng tổng doanh thu chung | PASS | PASS | PASS |

TC13–TC16 là bốn điều kiện phục vụ mô hình tám chiều; TC07 đánh giá theo chính sách làm sạch hiện hành của mã nguồn chứ không phải theo thiết kế giai đoạn 1.

## C. Kiểm tra toàn hệ thống (SQL 05)

| Kiểm tra | Mong đợi | Thực tế | Kết quả |
|---|---|---|:---:|
| Tám bảng chiều đủ dữ liệu | 8 | 8 | PASS |
| Dòng sự kiện thiếu khóa chiều hoặc sai độ đo | 0 | 0 | PASS |
| Số dòng bảng sự kiện = số dòng Staging | 9.024.814 | 9.024.814 | PASS |
| Tổng `total_amount` Staging = bảng sự kiện | 244.746.357,97 | 244.746.357,97 | PASS |
| Số dòng Staging = tổng `rows_loaded` trong log | 9.024.814 | 9.024.814 | PASS |
| Danh mục zone | 265 | 265 | PASS |
| Staging: đọc = nạp + loại | 0 batch sai | 0 batch sai | PASS |
| Không có batch ETL Failed | 0 | 0 | PASS |

**8/8 PASS.** Không có chuyến nào có khu vực đón nằm ngoài danh mục 265 vùng, `trip_count` luôn bằng 1 và `trip_duration` khớp thời gian đón–trả.

| Bảng | Số dòng | Bảng | Số dòng |
|---|---:|---|---:|
| `stg.taxi_zone` | 265 | `dds.dim_location` | 266 |
| `stg.yellow_trip` | 9.024.814 | `dds.dim_vendor` | 5 |
| `stg.yellow_trip_reject` | 422.562 | `dds.dim_payment_type` | 8 |
| `dds.dim_date` | 4.383 | `dds.dim_rate_code` | 8 |
| `dds.dim_time` | 1.440 | `dds.dim_passenger_group` | 4 |
| `dds.fact_trip` | 9.024.814 | `dds.dim_distance_band` | 6 |

## D. Test chức năng và hồi quy

| ID | Thao tác / input | Kỳ vọng | Trạng thái |
|---|---|---|---|
| TC17 | `python -m unittest discover -s tests -v` | 2 test method, kiểm tra tháng, 10 dòng fixture và mã lỗi kép | PASS – 2/2 test (`test_months`, `test_quality`), 0,037 s trong .venv và 0,042 s trong container Mage |
| TC18 | Chạy master cho một kỳ hai lần | Kỳ thứ hai bỏ qua, số dòng và tổng tiền không đổi | PARTIAL – đã quan sát kỳ đã nạp được bỏ qua qua cơ chế `meta.etl_load_control`; chưa lưu đối chiếu riêng `location_key` trước và sau |
| TC19 | Nạp kỳ mới sau các kỳ cũ | Kỳ mới được nạp, kỳ cũ giữ nguyên | PASS – nạp 2024-02 sau 2025-01 và 2024-01, tổng ba kỳ giữ nguyên 9.024.814 dòng và 244.746.357,97 USD, mỗi kỳ 16/16 PASS |
| TC20 | Tháng không có file (2025-12) | Dừng trước khi nạp, báo thiếu file; không tạo dữ liệu hay control cho kỳ | PASS – `Test-Path=False`, `FileNotFoundError` tại `run_master`, `meta.etl_load_control` không có dòng 2025-12, Staging theo source_file có 0 dòng |
| TC21 | Ngắt nạp Staging trên DB thử nghiệm, retry cùng file | Failed/Running cũ được ghi nhận; xóa phần dở theo source_file, nạp mới; đối soát PASS | NOT RUN |
| TC22 | Giả lập lỗi Fact trên DB thử nghiệm | Fact transaction rollback; Staging giữ nguyên; retry Fact | NOT RUN |
| TC23 | Tháng 2024 không có `cbd_congestion_fee` | Điền 0; nạp đúng schema | PASS – 2024: 5.771.745 chuyến, tổng CBD fee 0,00 USD, 0 NULL; 2025: 3.253.069 chuyến, tổng CBD fee 1.604.817,75 USD, 0 NULL |
| TC24 | `period_key=auto` với thư mục đã nạp hết, sau đó thử thêm tháng mới | Không nạp lại kỳ hoàn tất; chỉ xử lý kỳ mới | PARTIAL – lần chạy tự động theo lịch đã bỏ qua toàn bộ kỳ đã nạp và hoàn tất trong 3,4 giây; cần lưu thêm log CLI `--auto` phát hiện kỳ mới để đối chiếu kỳ cũ |
| TC25 | Kích hoạt lịch Mage và xem Pipeline runs | Trigger thực thi đúng biến auto, không overlap | PASS – Run ID 4 của pipeline `master_etl` tự kích hoạt đúng lịch `0 19 * * *` lúc 19:20 UTC 18/11 (02:20 19/11 giờ Việt Nam), block `run_master_etl` COMPLETED; từ các lần chạy trước đó đã ghi nhận lỗi hồi quy do mất biến `period_key` và đã khắc phục |
| TC26 | Tệp lịch sử thiếu LocationID | Báo schema không hỗ trợ; không đánh dấu Success | NOT RUN |
| TC27 | Dòng nghiệp vụ trùng hoàn toàn | Theo GĐ1 chỉ giữ một; mã hiện chưa khử trùng nghiệp vụ | GAP – thuộc tầng Staging, Hiệu xử lý và nhóm duyệt |
| TC28 | Cự ly 0/NULL | GĐ1 giữ và gán nhóm không hợp lệ; mã hiện loại ở Staging | GAP – nhóm quyết định trước khi nộp; hiện nhóm Invalid của `dim_distance_band` chỉ có 260 chuyến do cự ly trên 100 dặm |
| TC29 | Mô hình tám chiều | GĐ1 cần tám chiều; đã bổ sung đủ | PASS – đủ tám bảng chiều, 11 khóa chiều và hai độ đo `trip_count`, `trip_duration`; kiểm tra TC13–TC16 đạt ở cả ba kỳ |

## E. Kết quả chính thức của phiên kiểm thử (mô hình tám chiều)

| Kỳ | Source read | Valid | Reject | Fact | SUM stg | SUM fact | Kết quả |
|---|---:|---:|---:|---:|---:|---:|---|
| 2024-01 | 2.964.624 | 2.869.967 | 94.657 | 2.869.967 | 78.474.541,40 | 78.474.541,40 | 16/16 PASS |
| 2024-02 | 3.007.526 | 2.901.778 | 105.748 | 2.901.778 | 79.036.753,37 | 79.036.753,37 | 16/16 PASS |
| 2025-01 | 3.475.226 | 3.253.069 | 222.157 | 3.253.069 | 87.235.063,20 | 87.235.063,20 | 16/16 PASS |
| **Tổng** | **9.447.376** | **9.024.814** | **422.562** | **9.024.814** | **244.746.357,97** | **244.746.357,97** | **48/48 PASS** |

Tổng thực nghiệm: 9.447.376 dòng đọc, 9.024.814 dòng hợp lệ và dòng sự kiện, 422.562 dòng bị loại (4,47%), doanh thu 244.746.357,97 USD ở cả hai tầng. Thời gian nạp: Staging 252–328 giây, bảng sự kiện 132–183 giây mỗi kỳ.

### E.1. Minh chứng ETL (lịch sử Mage)

| Run | Pipeline | Thời điểm | Kết quả |
|---|---|---|---|
| ID 3 | `master_etl` | 18/11 12:53 → 13:02 (giờ VN) | COMPLETED, block `run_master_etl` hoàn tất sau 8 phút 46 giây cho kỳ 2024-02 |
| ID 4 | `master_etl` (trigger `master_etl_daily`) | 19/11 02:20 (giờ VN) = 18/11 19:20 UTC | COMPLETED sau 3,4 giây; tự kích hoạt đúng lịch `0 19 * * *`, bỏ qua toàn bộ kỳ đã nạp |

### E.2. Thống kê dữ liệu bị loại ở Staging

Tỷ lệ loại theo kỳ: 2024-01: 3,19%; 2024-02: 3,52%; 2025-01: 6,39%; toàn kho: 4,47%.

| Nhóm lý do | Số dòng | Tỷ lệ trong tổng reject |
|---|---:|---:|
| `DISTANCE_LE_ZERO` | 196.011 | 46,39% |
| `NEGATIVE_FARE;INVALID_TOTAL_AMOUNT` | 123.106 | 29,13% |
| `NEGATIVE_FARE` | 78.015 | 18,46% |
| Các tổ hợp còn lại | 25.430 | 6,02% |

Đếm theo từng quy tắc (một dòng vi phạm nhiều quy tắc được đếm ở từng quy tắc, không cộng lại được): `NEGATIVE_FARE` 222.221, `DISTANCE_LE_ZERO` 219.489, `INVALID_TOTAL_AMOUNT` 134.632, `DROPOFF_LE_PICKUP` 3.724, `OUT_OF_PERIOD` 55, `DURATION_EXCEEDS_24H` 48.

## F. Minh chứng và việc còn lại

- Tổng kiểm thử chính thức: 48 lượt SQL theo kỳ + 8 lượt SQL toàn kho + 2 unit test = **58/58 lượt PASS**.
- Ảnh minh chứng cần chụp: ảnh SQL 08 cho ba kỳ (mỗi kỳ 16 điều kiện PASS), ảnh SQL 05 đạt 8/8, ảnh số dòng tám bảng chiều, ảnh Mage trigger và Run ID 4.
- Xác nhận cấu hình trigger cuối cùng trong code bằng Update trigger in code và kiểm tra Git diff trước khi bàn giao.
- TC21, TC22, TC26 chỉ thực hiện trên môi trường thử nghiệm phù hợp nếu nhóm yêu cầu. TC27–TC28 là khác biệt thiết kế ở tầng Staging cần nhóm review. TC18 và TC24 còn thiếu minh chứng đối chiếu chi tiết.

## G. Tổng kết

| Trạng thái | Số test case | ID |
|---|---:|---|
| PASS | 22 | TC01–TC16, TC17, TC19, TC20, TC23, TC25, TC29 |
| PARTIAL | 2 | TC18, TC24 |
| NOT RUN | 3 | TC21, TC22, TC26 |
| GAP | 2 | TC27, TC28 |
| **Tổng** | **29** | TC01–TC29 |

- 58/58 lượt kiểm thử trong ba bộ kiểm thử chính thức đều PASS; không đồng nghĩa 29/29 test case PASS vì còn các mục PARTIAL, NOT RUN và GAP.
- Các yêu cầu kiểm thử đếm dòng, khóa ngoại, NULL, tổng tiền và toàn vẹn mô hình tám chiều đã được thực hiện. Scheduler đã tự kích hoạt đúng lịch.
- Hai khác biệt thiết kế còn mở (TC27 khử trùng nghiệp vụ, TC28 chính sách cự ly) đều ở tầng Staging, cần nhóm thống nhất trước khi nộp; nếu đổi chính sách thì số dòng và doanh thu phải nạp lại và cập nhật báo cáo.
