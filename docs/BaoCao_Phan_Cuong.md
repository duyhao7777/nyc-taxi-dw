# BÁO CÁO PHẦN VIỆC TẦNG DDS (STAGING → DDS)

**Học phần:** Kho dữ liệu & Kinh doanh thông minh (CSC12107)

**Người thực hiện:** Cường

**Phạm vi:** Thiết kế mô hình đa chiều 8 chiều + 1 bảng sự kiện, xây dựng pipeline nạp từ Staging sang DDS và kiểm tra đối soát dữ liệu.

## 1. Mục tiêu

Tầng Staging giữ dữ liệu chuyến đi **đã làm sạch** ở dạng bảng phẳng: mỗi dòng là một chuyến hợp lệ, kèm các mã nghiệp vụ dạng số (`vendor_id`, `rate_code_id`, `payment_type`, `pu_location_id`…). Để phục vụ truy vấn phân tích theo nhiều chiều và làm nền cho Power BI/SSAS ở giai đoạn 3, tầng DDS chuyển dữ liệu đó sang **mô hình sao gồm tám bảng chiều và một bảng sự kiện** theo thiết kế đã chốt ở giai đoạn 1.

Yêu cầu then chốt của lớp chuyển đổi này là chuyển dữ liệu **không làm thay đổi ý nghĩa**: giữ nguyên grain, giữ nguyên kiểu dữ liệu và giá trị tiền, để mọi kiểm tra đối soát giữa Staging và DDS đều thực hiện được bằng cách so sánh số dòng và tổng tiền.

Tầng DDS sử dụng:

- `dds.fact_trip` làm bảng sự kiện;
- tám bảng chiều `dim_date`, `dim_time`, `dim_location`, `dim_vendor`, `dim_payment_type`, `dim_rate_code`, `dim_passenger_group`, `dim_distance_band`;
- khóa thay thế cho các quan hệ giữa bảng sự kiện và các bảng chiều;
- thành viên `Unknown` trong mỗi bảng chiều nghiệp vụ để mã không tra cứu được vẫn có khóa hợp lệ;
- các cột lineage và metadata để truy vết ETL.

## 2. Luồng chuyển dữ liệu

Luồng nạp DDS được điều phối toàn bộ bởi pipeline `master_etl`, chạy theo từng kỳ `yyyy-MM`:

```text
taxi_zone_lookup.csv → stg.taxi_zone → sync_dim_location → dds.dim_location
script SQL sinh sẵn → dds.dim_date / dds.dim_time / dds.dim_vendor / dds.dim_payment_type / dds.dim_rate_code / dds.dim_passenger_group / dds.dim_distance_band
yellow_tripdata_*.parquet → stg.yellow_trip / stg.yellow_trip_reject → export_fact_trip (nối tám bảng chiều) → dds.fact_trip → đối soát Staging – DDS
```

Mỗi lần chạy `master_etl` thực hiện lần lượt: nạp danh mục vùng vào Staging → nạp chuyến đi vào Staging/Reject → đồng bộ `dim_location` → nạp bảng sự kiện → chạy bộ đối soát. Nếu một bước lỗi thì dừng ngay, không chạy tiếp bước sau.

## 3. Thiết kế mô hình DDS

### 3.1. Bảng sự kiện `fact_trip`

Grain: một dòng tương ứng đúng một chuyến đi hợp lệ trong `stg.yellow_trip` (một chuyến là một dòng sự kiện).

| Nhóm | Cột |
|---|---|
| Khóa chiều (vai trò đón) | `date_key`, `pickup_time_key`, `pu_location_key` |
| Khóa chiều (vai trò trả) | `dropoff_date_key`, `dropoff_time_key`, `do_location_key` |
| Khóa chiều (nghiệp vụ) | `vendor_key`, `payment_key`, `rate_code_key`, `passenger_group_key`, `distance_band_key` |
| Độ đo | `trip_count` (bằng 1 ở mỗi dòng), `trip_duration` (số phút từ lúc đón đến lúc trả), `passenger_count`, `trip_distance`, `fare_amount`, `tip_amount`, `total_amount`, `extra`, `mta_tax`, `tolls_amount`, `improvement_surcharge`, `congestion_surcharge`, `airport_fee`, `cbd_congestion_fee` |
| Truy vết | `stg_trip_id` (trỏ về dòng Staging), `batch_id` (lần nạp), `period_key` (tháng dữ liệu), `pickup_datetime`, `dropoff_datetime` |

Toàn bộ số tiền được giữ nguyên theo kiểu `DECIMAL(10,2)` để đối soát được giữa hai tầng.

### 3.2. Tám bảng chiều

| Bảng chiều | Khóa | Nguồn dữ liệu | Số dòng |
|---|---|---|---:|
| `dds.dim_date` | `date_key` dạng YYYYMMDD | sinh sẵn bằng script SQL: lịch 2015-01-01 → 2026-12-31, gồm ngày, tuần, tháng, quý, năm, thứ trong tuần và cờ cuối tuần | 4.383 |
| `dds.dim_time` | `time_key = giờ × 60 + phút + 1` | sinh sẵn: 1.440 phút trong ngày, chia bốn khung giờ | 1.440 |
| `dds.dim_location` | `location_key` | đồng bộ từ `stg.taxi_zone` (265 vùng) trong pipeline | 266 |
| `dds.dim_vendor` | `vendor_key` | danh mục mã 1, 2, 6, 7 kèm tên và ghi chú | 5 |
| `dds.dim_payment_type` | `payment_key` | danh mục mã 0–6 kèm tên và mô tả | 8 |
| `dds.dim_rate_code` | `rate_code_key` | danh mục mã 1–6 và 99 kèm tên biểu phí | 8 |
| `dds.dim_passenger_group` | `passenger_group_key` | suy ra từ số hành khách: 1; 2–4; 5–6; và Unknown | 4 |
| `dds.dim_distance_band` | `distance_band_key` | suy ra từ quãng đường: dưới 1; 1–3; 3–7; 7–15; từ 15 dặm trở lên; và không hợp lệ | 6 |

Bảy bảng chiều có dữ liệu cố định được **sinh sẵn bằng script DDL idempotent** (`sql/03_dds/03_dds_tables.sql`): chạy một lần trước khi nạp dữ liệu và có thể chạy lại bất cứ lúc nào mà không làm hỏng dữ liệu đang có. `dim_location` là chiều duy nhất phụ thuộc dữ liệu nguồn, được đồng bộ trong pipeline.

Mỗi bảng chiều nghiệp vụ có một thành viên `Unknown`; `dim_location` có dòng `Unknown` với `location_id = -1`. Nhờ vậy mọi khóa ngoại của bảng sự kiện đều tra cứu được.

### 3.3. Bảng ánh xạ từ Staging sang DDS

| Cột nguồn Staging | Đích trong `dds.fact_trip` | Cách chuyển đổi |
|---|---|---|
| `pickup_datetime` | `date_key` | khóa `YYYYMMDD` của ngày đón khách |
| `dropoff_datetime` | `dropoff_date_key` | khóa `YYYYMMDD` của ngày trả khách, nối với `dim_date` |
| `pickup_datetime`, `dropoff_datetime` | `pickup_time_key`, `dropoff_time_key` | khóa phút trong ngày theo công thức giờ × 60 + phút + 1, khớp `dim_time` |
| `pu_location_id`, `do_location_id` | `pu_location_key`, `do_location_key` | nối `dim_location` theo `location_id`, không khớp thì dùng Unknown |
| `vendor_id` | `vendor_key` | nối `dim_vendor` theo mã nhà cung cấp, không khớp thì dùng Unknown |
| `payment_type` | `payment_key` | nối `dim_payment_type` theo mã, không khớp thì dùng Unknown |
| `rate_code_id` | `rate_code_key` | nối `dim_rate_code` theo mã; mã 99 hoặc rỗng về thành viên Unknown |
| `passenger_count` | `passenger_group_key` | 1 → một người; 2–4 → nhóm nhỏ; 5–6 → nhóm lớn; rỗng, bằng 0 hoặc trên 6 → Unknown |
| `trip_distance` | `distance_band_key` | dưới 1; 1–3; 3–7; 7–15; từ 15 dặm trở lên; rỗng, không dương hoặc trên 100 dặm → không hợp lệ |
| (hệ thống) | `trip_count` | bằng 1 ở mỗi dòng, cộng lại ra số chuyến |
| `pickup_datetime`, `dropoff_datetime` | `trip_duration` | số phút từ lúc đón đến lúc trả |
| `passenger_count`, `trip_distance` | giữ nguyên | độ đo gốc, phục vụ tính tỷ lệ tiền boa và vận tốc |
| toàn bộ cột tiền | giữ nguyên | `DECIMAL(10,2)`, đối soát được |
| `stg_trip_id` | `stg_trip_id` | giữ để truy vết dòng nguồn |
| (từ `meta.etl_batch`) | `batch_id`, `period_key` | truy vết lần nạp và tháng dữ liệu |

Các quy tắc phân nhóm được áp dụng trực tiếp trong câu nạp bảng sự kiện; khung giờ chia Night 0–5, Morning 6–11, Afternoon 12–17 và Evening 18–23.

## 4. Quy trình nạp và kiểm soát

### 4.1. Nạp các bảng chiều

- Bảy chiều tra cứu tĩnh được sinh sẵn bằng script DDL idempotent, chạy một lần trước khi nạp dữ liệu.
- `dim_location` được đồng bộ bằng **UPDATE** các dòng đã tồn tại mà thuộc tính thay đổi và **INSERT** dòng mới, toàn bộ trong một transaction; **không xóa dữ liệu** vì các dòng này đang được `fact_trip` tham chiếu bằng khóa ngoại. Đây là cách áp dụng SCD loại 1: giữ danh mục hiện hành, cập nhật tên vùng khi thay đổi.

### 4.2. Nạp bảng sự kiện

Pipeline nạp (`mage_etl/data_exporters/export_fact_trip.py`) thực hiện:

1. **Kiểm tra tám chiều đã có đủ dữ liệu** theo số dòng tối thiểu của từng chiều; nếu thiếu thì dừng ngay với thông báo yêu cầu chạy script DDL.
2. Kiểm tra kỳ Staging đã nạp thành công trong `meta.etl_load_control`.
3. **Bỏ qua** kỳ đã có trạng thái `Success`.
4. Xóa dữ liệu của kỳ đang nạp lại, trong cùng transaction với lệnh nạp.
5. **Nạp bằng `INSERT ... SELECT` set-based** (một câu lệnh cho toàn bộ kỳ, không xử lý dòng bằng dòng): nối tám bảng chiều, suy ra khóa ngày và khóa giờ, suy ra nhóm hành khách và nhóm cự ly, dẫn mã lạ về Unknown.
6. **Kiểm tra sau khi nạp**: số dòng bảng sự kiện phải bằng số dòng Staging hợp lệ của kỳ, tổng `total_amount` hai tầng phải bằng nhau, và **không được có dòng nào thiếu khóa chiều hoặc sai độ đo** (`trip_count`, `trip_duration`); sai thì phát sinh lỗi và hoàn tác toàn bộ lần nạp.
7. Ghi `batch_id`, `rows_read`, `rows_loaded`, trạng thái batch và lỗi ETL vào schema `meta`, rồi đánh dấu kỳ nạp thành công.

Bảng sự kiện có khóa chính `fact_id` (clustered) và bốn chỉ mục phụ phục vụ đối soát và join: `IX_fact_trip_batch` (`batch_id`), `IX_fact_trip_period` (`period_key`), `IX_fact_trip_date` (`date_key`) và `IX_fact_trip_pu_do` (`pu_location_key`, `do_location_key`).

### 4.3. Idempotent, metadata và lịch chạy

- **Idempotent hai lớp:** kỳ đã nạp thành công được ghi nhận trong `meta.etl_load_control` và sẽ bị bỏ qua khi chạy lại; nếu nạp lại trong cùng một kỳ thì dữ liệu cũ của kỳ đó bị xóa theo `period_key` rồi nạp lại, nên chạy bao nhiêu lần cũng không sinh bản ghi trùng.
- **Metadata:** mỗi lần nạp ghi lại mã batch, số dòng đọc, số dòng nạp, thời điểm bắt đầu và kết thúc, trạng thái cùng thông báo lỗi vào `meta.etl_batch`; lỗi phát sinh ghi vào `meta.etl_error_log`. Mỗi dòng bảng sự kiện còn mang mã batch và mã kỳ dữ liệu để truy vết ngược.
- **Chống chạy song song:** `master_etl` dùng khoá ứng dụng của SQL Server (`sp_getapplock`) để không cho hai lần chạy cùng lúc.
- **Lịch chạy:** trigger `master_etl_daily` chạy theo lịch `0 19 * * *` (giờ UTC, tức 02:00 sáng theo giờ Việt Nam) với biến runtime `period_key = auto`, tự phát hiện các kỳ có file nguồn và bỏ qua kỳ đã nạp. Ngoài lịch có thể chạy thủ công cho một kỳ cụ thể bằng tham số `--months yyyy-MM`.

Mã nguồn của phần nạp nằm tại `mage_etl/data_exporters/sync_dim_location.py`, `mage_etl/data_exporters/export_fact_trip.py`, `mage_etl/pipelines/load_dds/metadata.yaml`, kèm bản sao tham khảo `mage_blocks/load_dds/`.

## 5. Kết quả nạp và đối soát

### 5.1. Phạm vi kiểm thử

Môi trường cục bộ được dựng lại hoàn toàn (SQL Server trong Docker, Mage trong container) ngày 18/11/2026, sau đó nạp lại dữ liệu nguồn từ TLC và chạy lại pipeline `master_etl` cho ba kỳ. Các số liệu dưới đây là kết quả chạy thực tế, đối chiếu khớp tuyệt đối với kết quả tích hợp của nhóm trước khi dựng lại môi trường.

### 5.2. Số liệu nạp theo kỳ

| Kỳ | Source đọc | Staging hợp lệ | Reject | Tỷ lệ reject | Bảng sự kiện | Doanh thu (USD) |
|---|---:|---:|---:|---:|---:|---:|
| 2024-01 | 2.964.624 | 2.869.967 | 94.657 | 3,19% | 2.869.967 | 78.474.541,40 |
| 2024-02 | 3.007.526 | 2.901.778 | 105.748 | 3,52% | 2.901.778 | 79.036.753,37 |
| 2025-01 | 3.475.226 | 3.253.069 | 222.157 | 6,39% | 3.253.069 | 87.235.063,20 |
| **Tổng** | **9.447.376** | **9.024.814** | **422.562** | **4,47%** | **9.024.814** | **244.746.357,97** |

Số dòng bảng sự kiện bằng đúng số dòng Staging hợp lệ và tổng `total_amount` hai tầng bằng nhau đến cent, cho cả ba kỳ.

### 5.3. Tám bảng chiều và mức sử dụng thực tế

| Bảng chiều | Số dòng | Bảng chiều | Số dòng |
|---|---:|---|---:|
| `dds.dim_date` | 4.383 | `dds.dim_rate_code` | 8 |
| `dds.dim_time` | 1.440 | `dds.dim_passenger_group` | 4 |
| `dds.dim_location` | 266 | `dds.dim_distance_band` | 6 |
| `dds.dim_vendor` | 5 | `dds.dim_payment_type` | 8 |

Phân bố chuyến theo từng chiều trên toàn bộ 9.024.814 chuyến, cho thấy tám chiều đều được sử dụng và có dữ liệu:

| Nhóm hành khách | Chuyến | Tỷ lệ | Khoảng cự ly | Chuyến | Tỷ lệ | Khung giờ | Chuyến | Tỷ lệ |
|---|---:|---:|---|---:|---:|---|---:|---:|
| Single_passenger | 6.528.787 | 72,34% | Under 1 mile | 2.090.992 | 23,17% | Night (0–5h) | 688.400 | 7,63% |
| Small_group (2–4) | 1.593.476 | 17,66% | 1 to 3 miles | 4.523.584 | 50,12% | Morning (6–11h) | 1.988.279 | 22,03% |
| Large_group (5–6) | 137.760 | 1,53% | 3 to 7 miles | 1.364.268 | 15,12% | Afternoon (12–17h) | 3.285.043 | 36,40% |
| Unknown | 764.791 | 8,47% | 7 to 15 miles | 656.892 | 7,28% | Evening (18–23h) | 3.063.092 | 33,94% |
| | | | 15 miles and up | 388.818 | 4,31% | | | |
| | | | Invalid | 260 | 0,003% | | | |

| Nhà cung cấp | Chuyến | Doanh thu (USD) | | Hình thức thanh toán | Chuyến | | Loại biểu phí | Chuyến |
|---|---:|---:|---|---|---:|---|---|---:|
| VTS (Curb Mobility) | 6.896.689 | 189.806.217,73 | | Credit card | 7.044.245 | | Standard rate | 7.911.743 |
| CMT | 2.127.551 | 54.917.669,36 | | Cash | 1.187.668 | | Unknown (mã 99/rỗng) | 772.155 |
| Myle | 574 | 22.470,88 | | Flex Fare | 677.458 | | JFK | 268.940 |
| Helix | 0 | 0 | | Dispute | 82.040 | | Negotiated fare | 31.813 |
| | | | | No charge | 33.403 | | Newark | 21.716 |
| | | | | | | | Nassau hoặc Westchester | 18.437 |
| | | | | | | | Group ride | 10 |

Ba kiểm tra bổ sung trên dữ liệu bảng sự kiện:

- **0** chuyến có khu vực đón nằm ngoài danh mục 265 vùng, tức không phải sinh dòng Unknown của `dim_location`.
- **0** chuyến có `dropoff_date_key` rỗng, tức mọi thời điểm trả khách đều nằm trong lịch 2015–2026.
- `trip_duration` bình quân **15,64 phút**, lớn nhất **1.440 phút**, đúng trần 24 giờ của quy tắc loại ở Staging.

### 5.4. Xử lý mã lạ và dữ liệu bất thường

| Tình huống | Số chuyến | Cách xử lý |
|---|---:|---|
| Khu vực đón nằm ngoài danh mục 265 vùng | 0 | dùng dòng Unknown của `dim_location` (không phát sinh) |
| `rate_code_id` rỗng hoặc bằng 99 | 772.155 | về thành viên Unknown của `dim_rate_code` |
| `passenger_count` rỗng, bằng 0 hoặc lớn hơn 6 | 764.791 | về nhóm Unknown của `dim_passenger_group` |
| `trip_distance` trên 100 dặm | 260 | về khoảng không hợp lệ của `dim_distance_band` |

### 5.5. Kết quả kiểm thử tự động

| Bộ kiểm tra | Nội dung | Kết quả |
|---|---|---|
| `sql/05_tests/05_reconcile_checks.sql` | 8 kiểm tra toàn kho: số dòng bảng sự kiện bằng Staging, tổng tiền bằng nhau, không batch Failed, 265 vùng, đủ tám chiều, không dòng nào thiếu khóa chiều | **8/8 PASS** |
| `sql/05_tests/08_master_period_checks.sql` | 16 kiểm tra theo từng kỳ (TC01–TC16), gồm kiểm tra tám chiều, toàn vẹn khóa chiều, `trip_count = 1` và `trip_duration` khớp thời gian đón–trả | **16/16 PASS** cho 2024-01, 2024-02 và 2025-01 (48/48 lượt) |

Bốn kiểm tra TC13–TC16 và hai kiểm tra toàn kho là phần bổ sung cho mô hình tám chiều.

### 5.6. Bối cảnh chất lượng nguồn

Tổng số dòng bị loại là 422.562, tương đương 4,47% số dòng đọc. Theo nhóm lý do (một dòng có thể vi phạm nhiều quy tắc):

| Nhóm lý do | Số dòng | Tỷ lệ trong tổng reject |
|---|---:|---:|
| `DISTANCE_LE_ZERO` | 196.011 | 46,39% |
| `NEGATIVE_FARE;INVALID_TOTAL_AMOUNT` | 123.106 | 29,13% |
| `NEGATIVE_FARE` | 78.015 | 18,46% |
| Các tổ hợp còn lại | 25.430 | 6,02% |

Đếm theo từng quy tắc (một dòng vi phạm nhiều quy tắc được đếm ở từng quy tắc, không cộng lại được): `NEGATIVE_FARE` 222.221, `DISTANCE_LE_ZERO` 219.489, `INVALID_TOTAL_AMOUNT` 134.632, `DROPOFF_LE_PICKUP` 3.724, `OUT_OF_PERIOD` 55, `DURATION_EXCEEDS_24H` 48.

### 5.7. Các lưu ý cần nêu rõ trong báo cáo

1. **Hạn chế về số hành khách:** 677.458 chuyến (7,51%) có `passenger_count` rỗng và đều thuộc nhóm thanh toán Flex Fare, nên tổng số hành khách thực tế cao hơn giá trị cộng được từ bảng sự kiện. Khi phân tích số hành khách phải nêu rõ hạn chế này và loại nhóm Unknown khỏi tổng.
2. **Khác biệt với thiết kế giai đoạn 1 về chính sách cự ly:** thiết kế giai đoạn 1 quy định chuyến có quãng đường bằng 0 hoặc âm chỉ được gán vào khoảng "không hợp lệ" chứ không bị loại ở Staging; mã hiện tại vẫn loại ở Staging nên khoảng không hợp lệ của `dim_distance_band` chỉ có 260 chuyến (do quãng đường trên 100 dặm). Đây là khác biệt đã ghi nhận, cần nhóm thống nhất trước khi nộp; nếu đổi chính sách thì số dòng và doanh thu phải chạy lại và cập nhật.
3. **Phạm vi của kiểm tra TC07:** kiểm tra "chuyến vi phạm còn lại" đánh giá theo chính sách làm sạch hiện hành của mã nguồn chứ không phải theo thiết kế giai đoạn 1, nên kết quả PASS không đồng nghĩa mọi quy tắc đã được áp dụng đầy đủ.
4. **Chưa khử trùng nghiệp vụ:** thiết kế giai đoạn 1 yêu cầu giữ một dòng khi trùng hoàn toàn, mã hiện tại chưa thực hiện bước này.
5. **Tên một số cột khác tên trong thiết kế giai đoạn 1** (`fact_id` tương ứng `trip_key`, `date_key` tương ứng `pickup_date_key`, `pu_location_key` tương ứng `pickup_location_key`, `day_num`, `week_num`… tương ứng `day`, `week`…): bảng ánh xạ đầy đủ nằm trong `docs/mapping.xlsx` (sheet `DDS_Dimensions` và `Fact_Trip`), nội dung và ý nghĩa cột không thay đổi.

### 5.8. Phạm vi kiểm thử

Phạm vi kiểm thử chính thức của phần DDS gồm ba kỳ dữ liệu 2024-01, 2024-02 và 2025-01, được nạp và kiểm tra trên môi trường dựng lại đầy đủ (SQL Server trong Docker, Mage trong container). Các số liệu trên đây ứng với đúng phạm vi này và đã được kiểm chứng bằng bộ kiểm thử tự động ở mục 5.5.

## 6. Kết luận

Tầng DDS đã hoàn thành theo mô hình tám chiều và một bảng sự kiện:

- Thiết kế đầy đủ các chiều Date, Time, Location, Vendor, Payment Type, Rate Code, Passenger Group và Distance Band, mỗi chiều có thành viên Unknown.
- `dds.fact_trip` lưu grain một chuyến đi cho một dòng, có 11 khóa chiều và đầy đủ độ đo nghiệp vụ.
- Pipeline nạp chạy set-based theo kỳ, idempotent, có metadata truy vết và chống chạy song song.
- Các chiều, thành viên Unknown và khóa ngoại bảo đảm không mất dữ liệu và không có khóa ngoại mồ côi.
- Kết quả nạp đạt đối soát số dòng và tổng tiền giữa Staging và DDS: **8/8 kiểm tra toàn kho PASS** và **48/48 kiểm tra theo kỳ PASS** cho ba kỳ 2024-01, 2024-02, 2025-01.

Phần mã DDL, pipeline và kiểm tra đối soát nằm tại `sql/03_dds/03_dds_tables.sql`, `mage_etl/data_exporters/`, `sql/05_tests/05_reconcile_checks.sql` và `sql/05_tests/08_master_period_checks.sql`; bảng ánh xạ nằm tại `docs/mapping.xlsx`; hướng dẫn dựng lại môi trường và chạy lại pipeline nằm tại `docs/HUONG_DAN_CAI_DAT_LAI.md`.
