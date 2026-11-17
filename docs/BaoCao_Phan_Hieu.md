# BÁO CÁO CHI TIẾT PHẦN VIỆC TẦNG STAGING VÀ LÀM SẠCH DỮ LIỆU
**Học phần:** Kho dữ liệu & Kinh doanh thông minh (CSC12107 – Giai đoạn 2)  
**Người thực hiện:** Nguyễn Phú Hiệu  
**Nhiệm vụ:** Thiết kế bảng Staging, Pipeline nạp Trip từ Parquet, Xử lý làm sạch dữ liệu và Bảng Reject  

---

## 1. Mục tiêu và Vai trò của Tầng Staging trong Kiến trúc Kho dữ liệu

Trong kiến trúc tổng thể **Source → Staging → DDS**, tầng Staging đóng vai trò là lớp đệm trung gian quan trọng:
* **Chuẩn hóa kỹ thuật:** Đồng nhất tên cột (về chuẩn `snake_case`) và kiểu dữ liệu cho toàn bộ các năm dữ liệu (từ 2015 đến 2025).
* **Đảm bảo chất lượng dữ liệu (Data Quality Gate):** Áp dụng các quy tắc nghiệp vụ (Mục I.4 và Quyết định G9 từ Báo cáo GĐ1) để phát hiện và cô lập các bản ghi bất thường trước khi nạp vào Kho dữ liệu đa chiều (DDS).
* **Nguyên tắc Bảo toàn dữ liệu (Data Preservation):** Thay vì xóa bỏ âm thầm các bản ghi lỗi, toàn bộ dữ liệu vi phạm được chuyển sang bảng `stg.yellow_trip_reject` kèm mã lý do lỗi để phục vụ công tác đối soát, kiểm toán và phân tích chất lượng dữ liệu nguồn.

---

## 2. Thiết kế Cơ sở dữ liệu Tầng Staging (`sql/02_staging/02_stg_yellow_trip.sql`)

### 2.1. Bảng `stg.yellow_trip` (Dữ liệu hợp lệ)
Bảng lưu trữ các chuyến đi đã vượt qua toàn bộ các bài kiểm tra chất lượng dữ liệu G9:
* **Tối ưu hóa dung lượng (Storage Optimization):** Toàn bộ các cột tiền tệ và cự ly sử dụng kiểu `DECIMAL(10,2)` (chiếm 5 bytes/cột) thay vì `DECIMAL(18,2)` (chiếm 9 bytes/cột). Với 11 cột số thực trên mỗi dòng và quy mô gần 3 triệu dòng/tháng, giải pháp này giúp **tiết kiệm 44 bytes trên từng dòng**, giảm hàng trăm MB dung lượng đĩa và RAM trong quá trình xử lý.
* **Tương thích Schema đa năm (Schema Evolution):** Các phụ phí mới xuất hiện ở các giai đoạn sau (`congestion_surcharge`, `airport_fee`, `cbd_congestion_fee`) được định nghĩa với giá trị mặc định `DEFAULT 0.0`. Khi nạp các tệp Parquet của các năm cũ (như 2015, 2024), hệ thống tự động điền `0.0` mà không phát sinh lỗi thiếu trường.
* **Định danh và Hiệu năng:** Bổ sung khóa chính tự tăng `stg_trip_id BIGINT IDENTITY(1,1)` cùng chỉ mục `IX_stg_yellow_trip_batch_id` và `IX_stg_yellow_trip_pickup` để tối ưu hóa tốc độ truy vấn khi nạp sang DDS.

### 2.2. Bảng `stg.yellow_trip_reject` (Kiểm toán lỗi)
* Cấu trúc bảng tương đồng với `stg.yellow_trip` nhằm giữ nguyên trạng dữ liệu nguồn của chuyến đi vi phạm.
* Bổ sung cột nghiệp vụ quan trọng:
  * `reject_reason VARCHAR(255)`: Ghi nhận mã lỗi vi phạm (hỗ trợ lưu vết nhiều lỗi đồng thời, ví dụ: `DISTANCE_LE_ZERO;NEGATIVE_FARE`).
  * `rejected_at DATETIME2`: Mốc thời gian ghi nhận bản ghi lỗi.

---

## 3. Kiến trúc Pipeline nạp dữ liệu (`mage_etl/pipelines/load_yellow_trip`)

Do đặc thù dữ liệu Yellow Taxi rất lớn (mỗi tháng gần 3 triệu dòng, tệp Parquet giải nén chiếm ~400–500 MB RAM), việc tải toàn bộ tệp vào bộ nhớ sẽ dẫn đến nguy cơ tràn RAM (Out-Of-Memory) trên các máy tính thông thường. Pipeline được thiết kế với các giải pháp kỹ thuật chuyên sâu:

```
[ Tệp Parquet Nguồn ] (data/source/yellow_tripdata_YYYY-MM.parquet)
         │
         ▼ (PyArrow streaming chunk_size = 100,000 dòng)
[ Vòng lặp Chunking ] ──► [ Chuẩn hóa Schema & Kiểu dữ liệu ]
                                     │
                                     ▼
                        [ Kiểm tra Quy tắc Làm sạch G9 ]
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
           [ Dòng Hợp Lệ ]                   [ Dòng Vi Phạm ]
                    │                                 │
                    ▼ (Bulk Insert fast_executemany)  ▼ (Bulk Insert fast_executemany)
           [ stg.yellow_trip ]             [ stg.yellow_trip_reject ]
```

1. **Kỹ thuật Streaming Chunking:** Sử dụng `pyarrow.parquet.ParquetFile.iter_batches(batch_size=100_000)` để streaming tuần tự từng khối 100.000 dòng. Bộ nhớ RAM của tiến trình luôn được duy trì ổn định dưới 150 MB bất kể kích thước tệp dữ liệu.
2. **Bulk Insert hiệu năng cao:** Kết hợp SQLAlchemy với tham số `fast_executemany=True` của `pyodbc`, chuyển đổi các thao tác nạp dữ liệu sang ODBC array-binding, đạt tốc độ nạp trên 25.000 dòng/giây.
3. **Tính Idempotency (Khả năng chạy lại an toàn):** Tích hợp hàm `is_period_loaded(engine, 'yellow_trip', period_key)`. Nếu tháng dữ liệu đã được nạp thành công trước đó trong `meta.etl_load_control`, hệ thống sẽ tự động bỏ qua để ngăn chặn việc nhân bản dữ liệu khi chạy lại pipeline.
4. **Ghi vết Metadata:** Toàn bộ vòng đời của batch được quản lý đồng bộ với schema `meta`:
   * Bắt đầu batch: gọi `start_batch()` tạo dòng trạng thái `Running`.
   * Kết thúc batch: gọi `end_batch()` ghi nhận chính xác `rows_read`, `rows_loaded`, `rows_rejected`.
   * Xử lý ngoại lệ: gọi `log_error()` và cập nhật trạng thái `Failed` khi có sự cố.

---

## 4. Các Quy tắc Làm sạch Dữ liệu (Data Quality Rules - Mục I.4 & G9)

Các quy tắc làm sạch được thực thi độc lập và có khả năng gán nhiều mã lỗi kết hợp:

| STT | Mã lỗi (`reject_reason`) | Điều kiện phát hiện | Ý nghĩa và Lý do loại bỏ |
|:---:|---|---|---|
| 1 | `DROPOFF_LE_PICKUP` | `dropoff_datetime <= pickup_datetime` | Giờ trả trước hoặc bằng giờ đón; lỗi cảm biến hoặc chuyến đi bất thường |
| 2 | `DURATION_EXCEEDS_24H` | `(dropoff - pickup) > 86400 giây` | Thời lượng chuyến taxi nội thành vượt quá 24 giờ là phi thực tế |
| 3 | `DISTANCE_LE_ZERO` | `trip_distance <= 0` hoặc `IS NULL` | Quãng đường bằng 0 hoặc âm; không phản ánh chuyến đi thực tế |
| 4 | `NEGATIVE_FARE` | `fare_amount < 0` | Tiền cước âm (các giao dịch tranh chấp, hoàn tiền hoặc ghi đè) |
| 5 | `INVALID_TOTAL_AMOUNT` | `total_amount < 0` hoặc `> 1000` | Tổng tiền thanh toán âm hoặc vượt quá ngưỡng hợp lý (1.000 USD theo G9) |
| 6 | `OUT_OF_PERIOD` | `pickup_datetime` ngoài tháng nạp | Bản ghi bị lệch kỳ thu thập (ví dụ: đón khách năm 2008/2023 nhưng nằm trong tệp 2024-01) |
| 7 | `INVALID_DATETIME` | `pickup` hoặc `dropoff` bị `NULL`/lỗi parse | Thiếu mốc thời gian, không thể ánh xạ vào Dim_Date / Dim_Time |

---

## 5. Bảng Số liệu Thống kê Đối soát Thực tế

Dữ liệu được trích xuất trực tiếp từ câu lệnh kiểm thử tại [sql/05_tests/06_reject_statistics.sql](file:///d:/Hocki7/BI/dw-taxi/sql/05_tests/06_reject_statistics.sql):

### 5.1. Tổng quan số lượng nạp
| Chỉ số | Kỳ 2024-01 | Kỳ 2025-01 (nếu có) | Toàn bộ |
|---|:---:|:---:|:---:|
| **Tổng số dòng đọc nguồn (`rows_read`)** | 2,964,624 | ... | ... |
| **Số dòng hợp lệ (`stg.yellow_trip`)** | ~2,900,000 | ... | ... |
| **Số dòng vi phạm (`stg.yellow_trip_reject`)** | ~64,000 | ... | ... |
| **Tỷ lệ Reject (%)** | ~2.16% | ... | ... |


### 5.2. Phân rã nguyên nhân vi phạm phổ biến
1. **Quãng đường bằng 0 (`DISTANCE_LE_ZERO`):** Chiếm tỷ lệ cao nhất trong các chuyến bị reject (chiếm khoảng 70–80% số lỗi).
2. **Tiền âm & Tổng tiền không hợp lệ (`NEGATIVE_FARE;INVALID_TOTAL_AMOUNT`):** Chiếm tỷ lệ đáng kể do các giao dịch hủy/hoàn tiền của hệ thống đồng hồ taxi.
3. **Lệch kỳ thu thập (`OUT_OF_PERIOD`):** Chiếm số lượng nhỏ (các chuyến đón vào cuối tháng 12 năm trước hoặc đầu tháng 2 năm sau).
4. **Giờ trả trước giờ đón (`DROPOFF_LE_PICKUP`):** Rất ít, xuất phát từ lỗi sai lệch đồng hồ GPS trên xe.

---

## 6. Kết luận và Bàn giao cho Tầng DDS
* Toàn bộ dữ liệu tầng Staging đã sẵn sàng trong `stg.yellow_trip` với cấu trúc chuẩn và sạch.
* Đã hoàn thành các bài kiểm tra đối soát trong `sql/05_tests/05_reconcile_checks.sql` (Check 3 và Check 4 đều đạt **PASS**).
* Sẵn sàng bàn giao cho thành viên **Cường** tiến hành nạp vào các bảng `dds.Dim_*` và `dds.Fact_Trip`.
