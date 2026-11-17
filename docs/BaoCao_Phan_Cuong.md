# BÁO CÁO CHI TIẾT PHẦN VIỆC TẦNG DDS (DIM VÀ FACT)
**Học phần:** Kho dữ liệu & Kinh doanh thông minh (CSC12107 – Giai đoạn 2)
**Người thực hiện:** Cường
**Nhiệm vụ:** Thiết kế bảng DDS, nạp Dim, nạp `dds.fact_trip`, viết phần báo cáo

---

## 1. Mục tiêu và Vai trò của Tầng DDS trong Kiến trúc Kho dữ liệu

Trong kiến trúc **Source → Staging → DDS**, tầng DDS là kho dữ liệu đa chiều phục vụ phân tích:
* **Mô hình sao (Star Schema):** Một bảng sự kiện trung tâm `dds.fact_trip` (grain: 1 dòng = 1 chuyến đi hợp lệ) được bao quanh bởi các bảng chiều `dds.dim_location` và `dds.dim_date`, tối ưu cho truy vấn OLAP và Power BI ở giai đoạn 3.
* **Khóa thay thế (Surrogate Key):** Dùng `location_key`, `date_key` thay cho khóa nghiệp vụ, cách ly kho khỏi biến động của hệ nguồn.
* **Bảo toàn đối soát:** Mọi quy tắc làm sạch G9 đã thực hiện ở Staging; DDS giữ nguyên grain và tổng tiền để hai check đối soát (check 5+6 file `05_reconcile_checks.sql`) đạt PASS.

---

## 2. Thiết kế Cơ sở dữ liệu Tầng DDS (`sql/03_dds/03_dds_tables.sql`)

### 2.1. Bảng `dds.dim_location` (chiều vị trí)
* Nguồn duy nhất: `stg.taxi_zone` (265 dòng đã kiểm chứng).
* `location_key INT IDENTITY(1,1)` khóa thay thế + `location_id INT UNIQUE` khóa tự nhiên 1–265, SCD loại 1 (đồng bộ ghi đè toàn phần mỗi lần nạp).
* Dòng `Unknown` (`location_id = -1`) để các chuyến có mã vùng lạ không bao giờ vi phạm FK.

### 2.2. Bảng `dds.dim_date` (chiều thời gian, sinh sẵn)
* Khóa `date_key INT` dạng `yyyymmdd`, sinh sẵn 2024-01-01 → 2026-12-31 (1.096 dòng) bằng CTE đệ quy, chạy lại an toàn nhờ `NOT EXISTS`.
* Thuộc tính: `year_num, quarter_num, month_num, day_num, day_of_week (DATEFIRST 1), is_weekend`.

### 2.3. Bảng `dds.fact_trip` (sự kiện chuyến đi)
* Grain 1:1 với `stg.yellow_trip` (giữ `stg_trip_id` để truy vết), gồm `date_key`, `pu/do_location_key` (FK), các chiều suy biến (`vendor_id, rate_code_id, payment_type`), toàn bộ measure tiền (`DECIMAL(10,2)`, giữ nguyên `total_amount` phục vụ đối soát), `batch_id` + `period_key` truy vết lần nạp.
* 4 non-clustered index trên `batch_id`, `period_key`, `date_key`, `(pu, do)` phục vụ đối soát và join.

---

## 3. Kiến trúc Pipeline nạp DDS (`mage_etl/pipelines/load_dds`)

```
[ stg.taxi_zone (265) ] ──► [ sync_dim_location ] ──► [ dds.dim_location (266) ]
        DELETE+INSERT toàn phần, idempotent

[ stg.yellow_trip ] ──► [ export_fact_trip ] ──► [ dds.fact_trip ]
  theo từng tháng (2024-01, 2024-02, 2025-01):
  is_period_loaded? ── Yes ──► bỏ qua
         │ No
         ▼ DELETE theo period_key + INSERT...SELECT set-based
           (JOIN dim_location, CROSS JOIN Unknown, date_key từ pickup_datetime)
         ▼ end_batch + mark_period_loaded
```

1. **Nạp set-based, không row-by-row:** Fact 9 triệu dòng được nạp bằng một câu `INSERT...SELECT` mỗi tháng (JOIN + lọc khoảng ngày sargable), hoàn thành ~3 phút/tháng thay vì hàng giờ.
2. **Tính Idempotency hai lớp:** `is_period_loaded(engine, 'fact_trip', period_key)` bỏ qua tháng đã `Success`; trong tháng thì `DELETE WHERE period_key` trước khi nạp lại, chạy lại pipeline không nhân bản.
3. **Ghi vết Metadata:** Mỗi tháng một `batch_id` qua `start_batch/end_batch` (`rows_read = rows_loaded`), lỗi ghi `meta.etl_error_log` qua `log_error()`, tháng xong ghi `meta.etl_load_control` qua `mark_period_loaded()`.
4. **Mã block được lưu vết:** `mage_etl/data_exporters/sync_dim_location.py`, `export_fact_trip.py` + `mage_etl/pipelines/load_dds/metadata.yaml`, kèm bản sao tham khảo `mage_blocks/load_dds/`.

---

## 4. Các Quy tắc Biến đổi Staging → DDS

| # | Quy tắc | Cách thực hiện |
|:---:|---|---|
| 1 | Tra cứu khóa vị trí | `JOIN dds.dim_location` theo `location_id`; `LEFT JOIN + COALESCE` về dòng Unknown (-1) cho mã lạ |
| 2 | Suy diễn khóa ngày | `date_key = YEAR*10000 + MONTH*100 + DAY` từ `pickup_datetime` |
| 3 | Lọc đúng kỳ | `pickup_datetime >= đầu tháng AND < đầu tháng sau` (thay vì so chuỗi) |
| 4 | Giữ grain và measure | Không gom nhóm, không đổi kiểu tiền; `total_amount` giữ nguyên để đối soát |
| 5 | Truy vết | Mọi dòng fact mang `batch_id` (→ `meta.etl_batch`) và `period_key` |

---

## 5. Bảng Số liệu Đối soát Thực tế

### 5.1. Tổng quan nạp DDS
| Chỉ số | 2024-01 | 2024-02 | 2025-01 | Tổng |
|---|:---:|:---:|:---:|:---:|
| Staging đọc (`rows_read`) | 2.964.624 | 3.007.526 | 3.475.226 | **9.447.376** |
| Fact nạp (`rows_loaded`) | 2.869.967 | 2.901.778 | 3.253.069 | **9.024.814** |
| Tỷ lệ giữ lại (%) | 96,81% | 96,48% | 93,61% | **95,53%** |

| Bảng DDS | Số dòng | Kỳ vọng | Kết quả |
|---|:---:|:---:|:---:|
| `dds.dim_location` | 266 | 265 + Unknown | ✔ |
| `dds.dim_date` | 1.096 | 2024–2026 | ✔ |
| `dds.fact_trip` | 9.024.814 | = `stg.yellow_trip` (check 5) | **PASS** |
| `SUM(total_amount)` stg vs fact | 244.746.357,97 = 244.746.357,97 (check 6) | bằng nhau | **PASS** |

### 5.2. Bối cảnh chất lượng nguồn (từ `06_reject_statistics.sql`, 422.562 dòng reject = 4,47%)
1. `DISTANCE_LE_ZERO` 196.011 (46,39%) — quãng đường zero, lỗi cảm biến GPS.
2. `NEGATIVE_FARE;INVALID_TOTAL_AMOUNT` 123.106 (29,13%) — giao dịch hủy/hoàn tiền.
3. `NEGATIVE_FARE` 78.015 (18,46%).
4. Các tổ hợp hiếm (`DURATION_EXCEEDS_24H`, `DROPOFF_LE_PICKUP`, `OUT_OF_PERIOD`…) chiếm phần còn lại — toàn bộ đã cô lập ở `stg.yellow_trip_reject`, không lọt vào fact.

---

## 6. Kết luận và Bàn giao
* Tầng DDS hoàn thành: `sql/03_dds/03_dds_tables.sql`, pipeline `load_dds` (2 block), mapping `docs/mapping.xlsx` (bản nháp chờ Huy chốt chính thức).
* Đối soát check 5+6 đạt **PASS**; `meta.etl_load_control` ghi nhận 6/6 `Success` (3 kỳ staging + 3 kỳ fact).
* Bàn giao cho **Huy** ghép pipeline tổng theo tháng và **Hảo** đối soát, tích hợp, đóng gói nộp.
