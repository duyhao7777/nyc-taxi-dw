# BÁO CÁO PHẦN VIỆC TẦNG DDS

**Học phần:** Kho dữ liệu & Kinh doanh thông minh (CSC12107)

**Người thực hiện:** Cường

**Phạm vi:** Thiết kế và nạp mô hình DDS, xây dựng pipeline Fact và kiểm tra đối soát dữ liệu.

## 1. Mục tiêu

Tầng DDS chuyển dữ liệu chuyến đi đã hợp lệ từ tầng Staging sang mô hình sao gồm 8 bảng chiều và 1 bảng sự kiện. Mô hình được thiết kế để phục vụ truy vấn phân tích, truy vết dữ liệu và nạp lại theo từng tháng.

Tầng DDS sử dụng:

- `dds.fact_trip` làm bảng Fact;
- 8 bảng Dimension: `dim_date`, `dim_time`, `dim_location`, `dim_vendor`, `dim_payment_type`, `dim_rate_code`, `dim_passenger_group`, `dim_distance_band`;
- khóa thay thế cho các quan hệ Fact–Dimension;
- đối tượng `Unknown` cho các mã không tra cứu được;
- khóa, cột lineage và metadata để truy vết ETL.

## 2. Thiết kế mô hình DDS

### 2.1. Bảng Fact

`dds.fact_trip` có grain: một dòng tương ứng với một chuyến đi hợp lệ trong `stg.yellow_trip`.

Các khóa tham chiếu gồm:

- `date_key`, `dropoff_date_key`;
- `pickup_time_key`, `dropoff_time_key`;
- `pu_location_key`, `do_location_key`;
- `vendor_key`, `payment_key`, `rate_code_key`, `passenger_group_key`, `distance_band_key`.

Các measure và thuộc tính nghiệp vụ gồm `trip_count`, `trip_duration`, thời gian đón/trả, quãng đường, số hành khách và các khoản tiền. Dữ liệu được nạp nguyên giá trị để thực hiện đối soát Staging–DDS. Hai cột `batch_id` và `period_key` lưu batch nạp và kỳ dữ liệu.

### 2.2. Các bảng Dimension

| Bảng | Khóa | Phạm vi dữ liệu |
|---|---|---|
| `dds.dim_date` | `date_key` dạng YYYYMMDD | Lịch từ 2015-01-01 đến 2026-12-31, gồm năm, quý, tháng, tuần, ngày trong tuần và ngày cuối tuần |
| `dds.dim_time` | `time_key = giờ × 60 + phút + 1` | 1.440 phút trong ngày, chia thành Night, Morning, Afternoon và Evening |
| `dds.dim_location` | `location_key` | 265 zone từ `stg.taxi_zone`, có thêm dòng Unknown |
| `dds.dim_vendor` | `vendor_key` | Mã nhà cung cấp 1, 2, 6, 7 và dòng Unknown |
| `dds.dim_payment_type` | `payment_key` | Mã thanh toán 0 đến 6 và dòng Unknown |
| `dds.dim_rate_code` | `rate_code_key` | Mã biểu phí 1 đến 6, 99 và dòng Unknown |
| `dds.dim_passenger_group` | `passenger_group_key` | Single, Small group, Large group và Unknown |
| `dds.dim_distance_band` | `distance_band_key` | Under 1, 1–3, 3–7, 7–15, 15 miles and up và Invalid |

Các quy tắc phân nhóm được áp dụng trực tiếp trong câu nạp Fact:

- Nhóm hành khách: 1; 2–4; 5–6; các trường hợp rỗng, 0 hoặc trên 6 được gán Unknown.
- Khoảng cự ly: dưới 1 dặm; 1–3 dặm; 3–7 dặm; 7–15 dặm; từ 15 dặm trở lên; cự ly rỗng, không dương hoặc trên 100 dặm thuộc Invalid.
- Khung giờ: Night 0–5, Morning 6–11, Afternoon 12–17 và Evening 18–23.

`dim_location`, `dim_vendor`, `dim_payment_type`, `dim_rate_code`, `dim_passenger_group` và `dim_distance_band` có thành viên Unknown để mọi khóa ngoại của Fact đều có thể tra cứu hợp lệ.

DDL nằm trong `sql/03_dds/03_dds_tables.sql` và được thiết kế idempotent. Các thành phần tra cứu tĩnh được sinh hoặc đồng bộ bằng script DDL; `dim_location` được đồng bộ riêng với dữ liệu Taxi Zones.

## 3. Quy trình nạp dữ liệu

Luồng nạp DDS như sau:

```text
stg.taxi_zone --> sync_dim_location --> dds.dim_location
stg.yellow_trip --> export_fact_trip  --> dds.fact_trip
```

Pipeline nạp Fact thực hiện:

1. Kiểm tra 8 Dimension đã có đủ dữ liệu.
2. Kiểm tra kỳ Staging đã nạp thành công.
3. Bỏ qua kỳ đã có trạng thái `Success` trong metadata.
4. Xóa dữ liệu Fact của kỳ trước khi nạp lại.
5. Nạp Fact bằng `INSERT ... SELECT` set-based trong một transaction.
6. Kiểm tra số dòng và khóa Dimension trước khi ghi trạng thái thành công.
7. Ghi `batch_id`, `rows_read`, `rows_loaded`, trạng thái batch và lỗi ETL vào schema `meta`.

Phần Location được nạp bằng `MERGE`/đồng bộ update–insert, không xóa Dimension đang được Fact tham chiếu. Fact được ánh xạ qua ngày, giờ, zone và các Dimension nghiệp vụ. Các mã không tìm thấy được `COALESCE` về dòng Unknown.

Mã nguồn của phần nạp nằm tại:

- `mage_etl/data_exporters/sync_dim_location.py`;
- `mage_etl/data_exporters/export_fact_trip.py`;
- `mage_etl/pipelines/load_dds/metadata.yaml`;
- bản sao tham khảo `mage_blocks/load_dds/`.

## 4. Quy tắc chuyển đổi Staging sang DDS

| Quy tắc | Cách thực hiện |
|---|---|
| Ngày đón/trả | Tạo khóa `YYYYMMDD` từ `pickup_datetime` và `dropoff_datetime` |
| Giờ đón/trả | Tính khóa phút trong ngày bằng giờ, phút |
| Location | Join theo `location_id`, không khớp thì dùng Unknown |
| Vendor, Payment, Rate code | Join theo mã nguồn, không khớp thì dùng Unknown |
| Nhóm hành khách | Phân loại bằng `passenger_count` |
| Khoảng cự ly | Phân loại bằng `trip_distance` |
| Measure | `trip_count = 1`; `trip_duration = DATEDIFF(MINUTE, pickup, dropoff)` |
| Giữ grain | Không gom nhóm dòng chuyến; lưu `stg_trip_id` để truy vết |
| Đúng kỳ | Nạp theo `pickup_datetime >= đầu tháng` và `< đầu tháng sau` |
| Đối soát tiền | Giữ và nạp nguyên `total_amount` theo kiểu DECIMAL |

## 5. Kết quả nạp và đối soát

Các kiểm tra `05_reconcile_checks.sql` xác nhận:

- Số dòng Fact bằng số dòng Staging hợp lệ.
- Tổng `total_amount` của Staging bằng Fact.
- Không có batch ETL trạng thái Failed.
- Danh mục zone có 265 dòng.
- Các bảng Dimension có đủ dữ liệu.
- Không có dòng Fact thiếu khóa Dimension hoặc measure hợp lệ.

Kết quả tích hợp được nạp ở 5 kỳ `2024-01`, `2024-02`, `2025-01`, `2025-05` và `2025-06`:

| Chỉ số | Kết quả |
|---|---:|
| Số dòng Staging hợp lệ | 16.988.701 |
| Số dòng Fact | 16.988.701 |
| Tổng tiền Staging | 478.610.999,06 USD |
| Tổng tiền Fact | 478.610.999,06 USD |
| Số dòng bảng Dimension | Đạt các ngưỡng yêu cầu của GĐ1 |

## 6. Kết luận

Tầng DDS đã hoàn thành theo mô hình 8 Dimension và 1 Fact:

- Thiết kế đầy đủ các Dimension Date, Time, Location, Vendor, Payment Type, Rate Code, Passenger Group và Distance Band.
- `dds.fact_trip` lưu grain một chuyến đi cho một dòng, có 11 khóa Dimension và các measure nghiệp vụ.
- Pipeline nạp Fact chạy set-based theo kỳ, idempotent và có metadata truy vết.
- Các Dimension, mã Unknown và khóa ngoại bảo đảm không bị mất dữ liệu hoặc orphan key.
- Kết quả nạp 5 kỳ đã đạt đối soát số dòng và tổng tiền giữa Staging và DDS.

Phần mã DDL, pipeline và kiểm tra đối soát nằm tại `sql/03_dds/03_dds_tables.sql`, `mage_etl/data_exporters/`, `sql/05_tests/05_reconcile_checks.sql` và `sql/05_tests/08_master_period_checks.sql`.
