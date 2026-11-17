# TEST PLAN – NYC Yellow Taxi DW, giai đoạn 2

## A. Kế hoạch kiểm thử SQL

Chạy `sql/05_tests/08_master_period_checks.sql` cho từng kỳ (đổi `@k`). Kết quả thực nghiệm trên SQL Server của Huy, ngày 17–18/11/2026: **TC01–TC12 đều PASS ở cả năm kỳ 2024-01, 2024-02, 2025-01, 2025-05 và 2025-06 (60/60 lượt kiểm thử)**. PASS chỉ áp dụng cho điều kiện trong script hiện tại.

Phạm vi thực nghiệm gồm ba kỳ ban đầu và hai kỳ mở rộng 2025-05, 2025-06; cả năm kỳ đã có ảnh SQL 08.

Quy ước: PASS = có minh chứng đạt; PARTIAL = đã kiểm tra một phần kỳ vọng; NOT RUN = chưa thực hiện; GAP = khác biệt với thiết kế GĐ1 chưa xử lý.

| ID | Nội dung | Kết quả mong đợi | Bằng chứng | 2024-01 | 2024-02 | 2025-01 | 2025-05 | 2025-06 |
|---|---|---|---|---|---|---|---|---|
| TC01 | Danh mục Zone | 265 mã 1–265 | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC02 | Source → Staging | log read = valid + reject; loaded/rejected khớp bảng | SQL 08 (đối soát log với bảng; chưa kiểm tra độc lập Parquet metadata) | PASS | PASS | PASS | PASS | PASS |
| TC03 | Staging → Fact | số dòng bằng nhau | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC04 | Tổng doanh thu | SUM(total_amount) khớp đến cent | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC05 | Grain fact | Không trùng stg_trip_id trong kỳ | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC06 | FK và lineage | Không có orphan date/location/stg | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC07 | Valid theo code hiện tại | Không còn bản ghi vi phạm các rule reject | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC08 | Reject reason | Không rỗng | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC09 | Metadata | 2 control Success tham chiếu batch Success cùng kỳ | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC10 | Truy vết nguồn | source_row_number không trùng hoặc NULL giữa valid/reject | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC11 | Tổng tiền NULL | 0 dòng; nếu fail cần thống nhất policy | SQL 08 | PASS | PASS | PASS | PASS | PASS |
| TC12 | Calendar | Đủ ngày trong tháng | SQL 08 | PASS | PASS | PASS | PASS | PASS |

## B. Test chức năng và hồi quy

| ID | Thao tác / input | Kỳ vọng | Trạng thái |
|---|---|---|---|
| TC13 | `python -m unittest discover -s tests -v` | 2 test method, kiểm tra tháng, 10 dòng fixture và mã lỗi kép | PASS – thực thi thực tế trong .venv, 2/2 test (`test_months`, `test_quality`), lần cuối 0,037 s |
| TC14 | Chạy master 2025-01 hai lần | Trip & Fact skip lần 2, số dòng/tổng tiền và location_key không đổi | PARTIAL – log skip 2025-01, 7/7 checks True, số dòng và doanh thu kỳ không đổi; chưa đối chiếu riêng location_key trước/sau |
| TC15 | Chạy tháng mới 2024-01 và 2024-02 sau 2025-01 | Nạp kỳ yêu cầu, kỳ cũ giữ nguyên | PARTIAL – hai kỳ mới 12/12 PASS mỗi kỳ; đã đối soát tổng kho năm tháng; chưa lưu đối chiếu riêng từng kỳ cũ trước/sau khi nạp kỳ mới |
| TC16 | Tháng không có file (2025-12) | Dừng trước nạp Zones, báo thiếu file; không tạo dữ liệu hoặc control cho kỳ | PASS – Test-Path=False; FileNotFoundError tại run_master, dòng 47; meta.etl_load_control không có dòng 2025-12; Staging theo source_file có 0 dòng |
| TC17 | Ngắt nạp Staging trên DB thử nghiệm, retry cùng file | Failed/Running cũ được ghi nhận; xóa phần dở theo source_file, nạp mới; đối soát PASS | NOT RUN |
| TC18 | Giả lập lỗi Fact trên DB thử nghiệm | Fact transaction rollback; staging giữ nguyên; retry Fact | NOT RUN |
| TC19 | Tháng 2024 không có cbd_congestion_fee | Điền 0; nạp đúng schema | PASS – trong phạm vi 2024–2025: 5.771.745 chuyến năm 2024, tổng CBD fee 0,00 USD; 11.216.956 chuyến năm 2025, tổng CBD fee 5.993.834,50 USD; cả hai năm 0 NULL; chưa xác minh toàn bộ schema lịch sử |
| TC20 | `period_key=auto` với thư mục đã nạp hết, sau đó thử thêm tháng mới | Không nạp lại kỳ hoàn tất; chỉ xử lý kỳ mới | PARTIAL – Run ID 2 trên Mage Done, 1/1 block test PASS; hai kỳ mới đã đạt 12/12 SQL PASS; cần bổ sung log CLI auto phát hiện kỳ mới và đối chiếu kỳ cũ để xác nhận đầy đủ |
| TC21 | Kích hoạt lịch Mage và xem Pipeline runs | Trigger thực thi đúng biến auto, không overlap | PARTIAL – Run ID 3, 4 Failed khi thiếu period_key; sau sửa Run ID 5 Done (17:32 UTC); đã bật skip if running, chưa thử tình huống overlap thực tế |
| TC22 | Tệp lịch sử thiếu LocationID | Báo schema không hỗ trợ; không đánh dấu Success | NOT RUN |
| TC23 | Dòng nghiệp vụ trùng hoàn toàn | Theo GĐ1 chỉ giữ một; code hiện chưa khử trùng nghiệp vụ | GAP – Hiệu xử lý/nhóm duyệt |
| TC24 | Cự ly 0/NULL | GĐ1 giữ Invalid; code hiện reject | GAP – nhóm quyết định trước khi nộp |
| TC25 | Mô hình 8 Dimension | GĐ1 cần 8; repo có 2 | GAP – Cường/nhóm quyết định |

## C. Trình tự chạy và chụp minh chứng

1. Chạy DDL theo README, kể cả `03_dds_tables.sql`. Không DROP database đang có dữ liệu; dùng database thử nghiệm riêng nếu kiểm thử lỗi.
2. Chạy unit test. Chạy master cho ba tháng gốc và hai tháng mở rộng. Chạy SQL 08 theo từng tháng và SQL 05/06 toàn hệ thống.
3. Ghi lại count, doanh thu, batch ID và location_key trước/sau lần rerun. Đối chiếu source metadata với log. Kiểm tra lỗi lịch sử riêng, không xem một batch Failed lịch sử là thất bại của batch mới đã retry.
4. Lưu minh chứng auto với tháng mới (mục F); test thiếu file đã thực hiện (mục G); test lỗi giữa chừng chỉ chạy trên DB thử nghiệm nếu cần. Không xóa log để tạo PASS.

## D. Kết quả chạy bản tích hợp (17–18/11/2026)

| Kỳ | Source read | Valid | Reject | Fact | SUM stg | SUM fact | PASS/FAIL | Ảnh/log |
|---|---:|---:|---:|---:|---:|---:|---|---|
| 2024-01 | 2.964.624 | 2.869.967 | 94.657 | 2.869.967 | 78.474.541,40 | 78.474.541,40 | 12/12 PASS | Ảnh SQL 08 – 2024-01 |
| 2024-02 | 3.007.526 | 2.901.778 | 105.748 | 2.901.778 | 79.036.753,37 | 79.036.753,37 | 12/12 PASS | Ảnh SQL 08 – 2024-02 |
| 2025-01 | 3.475.226 | 3.253.069 | 222.157 | 3.253.069 | 87.235.063,20 | 87.235.063,20 | 12/12 PASS | Ảnh SQL 08 – 2025-01 |
| 2025-05 | 4.591.845 | 4.093.463 | 498.382 | 4.093.463 | 119.861.989,70 | 119.861.989,70 | 12/12 PASS | Ảnh SQL 08 – 2025-05 |
| 2025-06 | 4.322.960 | 3.870.424 | 452.536 | 3.870.424 | 114.002.651,39 | 114.002.651,39 | 12/12 PASS | Ảnh SQL 08 – 2025-06 |
| **Tổng** | **18.362.181** | **16.988.701** | **1.373.480** | **16.988.701** | **478.610.999,06** | **478.610.999,06** | **60/60 PASS** | Tổng theo kỳ |

## E. Minh chứng và công việc còn lại

- Tổng thực nghiệm: 18.362.181 dòng đọc, 16.988.701 dòng hợp lệ/Fact, 1.373.480 reject; doanh thu 478.610.999,06 USD ở cả hai tầng.
- Mage Run ID 1 (manual): Done, 50,66 giây, 7/7 checks True cho 2025-01. Run ID 2 (auto kích hoạt thủ công): Done, 10,13 giây, 1/1 block test PASS. Run ID 5: Scheduler tự chạy theo cron thử nghiệm, Done; lịch chính thức đã khôi phục về `0 19 * * *`.
- Lỗi hồi quy: Run ID 3–4 Failed sau khi sửa trigger làm mất `period_key`; khắc phục bằng thêm lại biến và mặc định `kwargs.get('period_key') or 'auto'`. Không xóa các run lỗi khỏi minh chứng.
- Đã đối soát số dòng toàn kho sau khi nạp năm tháng và chạy kiểm thử. Cần lưu ảnh minh chứng; xác nhận trạng thái active và cấu hình trigger cuối trong code bằng Update trigger in code, kiểm tra Git diff trước khi bàn giao.
- 60 lượt SQL theo kỳ + 6 lượt SQL đối soát toàn kho + 2 unit test = 68/68 lượt PASS (không cộng các truy vấn minh chứng riêng hoặc test Mage vào mẫu số này). TC16 và TC19 đã PASS; TC17–18, TC22 chưa chạy; TC23–25 còn GAP.

## F. Kiểm thử mở rộng – MR2 và chế độ auto

Hai kỳ 2025-05 và 2025-06 đã nạp thành công theo kết quả SQL 08: 24/24 lượt PASS. Cặp kỳ đã sẵn sàng để phân tích MR2 theo quy tắc hiện tại. Để hoàn tất TC20, lưu thêm log `--auto` xác nhận phát hiện kỳ mới và bỏ qua kỳ cũ; ảnh SQL không tự chứng minh cách kích hoạt ETL. Không cần nạp lại dữ liệu để lấy minh chứng. Đã kiểm tra dung lượng ROWS và đối soát toàn kho; bật lại trigger `master_etl_daily` với cron `0 19 * * *`, `period_key=auto` sau khi hoàn tất.

## G. Kết quả kiểm thử bổ sung và đối soát toàn kho

### G.1. Kiểm thử thiếu file (TC16)

```powershell
Test-Path "$env:DATA_DIR\yellow_tripdata_2025-12.parquet"
python scripts/run_master_etl.py --months 2025-12
```

Kết quả: `False`, sau đó `FileNotFoundError` tại `run_master` (dòng 47). Đây là lỗi mong đợi trong kiểm thử âm, không phải lỗi cần sửa.

```sql
USE NYCTaxi_DW;
SELECT * FROM meta.etl_load_control WHERE period_key = '2025-12';
SELECT COUNT_BIG(*) AS total_trips FROM stg.yellow_trip
WHERE source_file LIKE '%2025-12.parquet';
```

Control: không có bản ghi; total_trips: 0. **PASS.** Minh chứng: terminal và ảnh kết quả hai truy vấn.

### G.2. Schema Evolution (TC19)

```sql
SELECT YEAR(pickup_datetime) AS trip_year,
       COUNT_BIG(*) AS total_trips,
       SUM(cbd_congestion_fee) AS total_cbd_fee,
       COUNT_BIG(*) - COUNT_BIG(cbd_congestion_fee) AS null_count
FROM stg.yellow_trip
GROUP BY YEAR(pickup_datetime)
ORDER BY trip_year;
```

| Năm | Số chuyến | Tổng CBD fee (USD) | NULL | Kết quả |
|---|---:|---:|---:|---|
| 2024 | 5.771.745 | 0,00 | 0 | PASS |
| 2025 | 11.216.956 | 5.993.834,50 | 0 | PASS |

Chỉ xác nhận tương thích schema và chuẩn hóa CBD fee trong các kỳ 2024–2025 đã nạp.

### G.3. SQL 05 – Đối soát toàn hệ thống

File: `sql/05_tests/05_reconcile_checks.sql`.

| Kiểm tra | Mong đợi | Thực tế | Kết quả |
|---|---|---|---|
| Fact rows = Staging rows | 16.988.701 | 16.988.701 | PASS |
| No failed ETL batches | 0 | 0 | PASS |
| Staging read = loaded + rejected | 0 batch sai | 0 batch sai | PASS |
| Taxi Zones | 265 | 265 | PASS |
| Staging rows = SUM(rows_loaded) trong log | 16.988.701 | 16.988.701 | PASS |
| SUM(total_amount) Staging = Fact (USD) | 478.610.999,06 | 478.610.999,06 | PASS |

**6/6 PASS.** Không có batch Failed trong metadata theo script SQL tại thời điểm kiểm tra; lịch sử Mage vẫn có Run ID 3 và 4 Failed trước khi sửa tham số.

Truy vấn đối soát độc lập toàn kho cũng xác nhận Staging và DDS cùng có 16.988.701 dòng và tổng doanh thu 478.610.999,06 USD.

| Bảng | Số dòng thực tế |
|---|---:|
| stg.taxi_zone | 265 |
| stg.yellow_trip | 16.988.701 |
| stg.yellow_trip_reject | 1.373.480 |
| dds.dim_date | 4.383 |
| dds.dim_location | 266 |
| dds.fact_trip | 16.988.701 |

### G.4. SQL 06 – Thống kê Reject

File: `sql/05_tests/06_reject_statistics.sql`. Thực thi thành công; đây là thống kê, không phải bộ assertion PASS/FAIL.

| Kỳ | Tỷ lệ Reject (%) |
|---|---:|
| 2024-01 | 3,19 |
| 2024-02 | 3,52 |
| 2025-01 | 6,39 |
| 2025-05 | 10,85 |
| 2025-06 | 10,47 |
| Toàn kho | 7,48 |

| Nhóm reject_reason (5 nhóm lớn nhất) | Số dòng | Tỷ lệ trong Reject (%) |
|---|---:|---:|
| NEGATIVE_FARE | 452.168 | 32,92 |
| DISTANCE_LE_ZERO | 412.146 | 30,01 |
| NEGATIVE_FARE;INVALID_TOTAL_AMOUNT | 293.767 | 21,39 |
| DROPOFF_LE_PICKUP | 130.822 | 9,52 |
| NEGATIVE_FARE;DISTANCE_LE_ZERO | 50.980 | 3,71 |

Các nhóm là giá trị nguyên vẹn của reject_reason, không phải tần suất độc lập từng mã lỗi. Quy tắc reject hiện tại chưa hoàn toàn khớp GĐ1 (TC24).

## H. Tổng kết và bàn giao

| Trạng thái | Số test case | ID |
|---|---:|---|
| PASS | 15 | TC01–TC13, TC16, TC19 |
| PARTIAL | 4 | TC14, TC15, TC20, TC21 |
| NOT RUN | 3 | TC17, TC18, TC22 |
| GAP | 3 | TC23–TC25 |
| Tổng | 25 | TC01–TC25 |

- 60/60 lượt SQL theo kỳ, 6/6 lượt SQL toàn kho, 2/2 unit test: **68/68 lượt PASS** trong ba bộ kiểm thử này. Không đồng nghĩa 25/25 test case PASS.
- Các yêu cầu kiểm thử đếm dòng, khóa ngoại, NULL, tổng tiền trong phân công đã được thực hiện. Scheduler đã tự kích hoạt thành công; chưa thử overlap. TC20 còn thiếu log auto phát hiện file mới; không nạp lại chỉ để lấy minh chứng.
- TC17, TC18, TC22 chỉ thực hiện trên môi trường thử nghiệm phù hợp nếu nhóm yêu cầu. TC23–TC25 cần nhóm review và thống nhất khác biệt thiết kế.
