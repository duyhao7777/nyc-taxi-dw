# NYC Yellow Taxi Data Warehouse (CSC12107 – Giai đoạn 2)

Kiến trúc 3 tầng **Source → Staging → DDS**. Công cụ: **SQL Server + Mage AI** (Power BI và SSAS dùng ở giai đoạn 3).

**Hạn nộp: 22:00 Thứ Năm 19/11/2026** (nên nộp tối 18/11). Bài nộp: `MaNhom_BaoCao.pdf` và `MaNhom_Src.zip`.

## 1. Kiến trúc

| Tầng | Là gì | Nằm ở đâu |
|---|---|---|
| Source | Tệp nguồn: Yellow Taxi Trip (Parquet), Taxi Zones (CSV), Shapefile | `data/source/` (**không** đưa lên GitHub) |
| Staging | Dữ liệu đã nạp vào SQL Server, chuẩn hóa tên và kiểu, làm sạch | schema `stg` trong database `NYCTaxi_DW` |
| DDS | Kho đa chiều: các bảng Dim và Fact | schema `dds` |
| Metadata | Log mỗi lần chạy ETL, lỗi, tháng nào đã nạp, từ điển dữ liệu | schema `meta` |

Cả nhóm dùng **một database `NYCTaxi_DW`** với 3 schema `stg`, `dds`, `meta`. Mỗi người chạy database trên máy mình; mã nguồn dùng chung qua GitHub.

## 2. Cấu trúc thư mục

```
sql/00_setup       tạo database và schema
sql/02_staging     bảng Staging
sql/03_dds         bảng Dim, Fact
sql/04_metadata    bảng Metadata
sql/05_tests       script kiểm thử, đối soát
mage_etl/          project Mage (ĐÃ CÓ SẴN, không chạy mage init)
mage_etl/utils/    etl_common.py: hàm kết nối SQL Server và ghi Metadata
mage_blocks/       bản sao mã các block (để tham khảo, mẫu cho pipeline mới)
mage_extras/       bản gốc của etl_common.py
scripts/           tải dữ liệu
docs/              báo cáo, mapping, sơ đồ
```

## 3. Cài đặt (làm một lần trên máy của mình)

### 3.1. Phần mềm cần cài

- **SQL Server** (Developer hoặc Express) và **SSMS**.
- **ODBC Driver 18 for SQL Server** (hoặc 17).
- **Python 3.10** (hoặc 3.11). **Không dùng Python 3.13 hoặc 3.14**, vì `mage-ai` sẽ báo lỗi khi cài Pillow.
- **Git**.

### 3.2. Lấy mã nguồn về đường dẫn NGẮN

```
git clone https://github.com/<tai-khoan>/nyc-taxi-dw.git C:\dw-taxi
cd C:\dw-taxi
```

Đặt repo ở đường dẫn ngắn, không dấu, không khoảng trắng (ví dụ `C:\dw-taxi`). Nếu để trong `C:\Users\...\Downloads\nyc-taxi-dw`, Mage sẽ báo lỗi `unicodeescape` vì các đoạn `\U`, `\n` trong đường dẫn.

### 3.3. Tạo môi trường ảo và cài thư viện

```
py -3.10 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Nếu PowerShell chặn script, chạy trước: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

Kiểm tra: `python --version` phải hiện `Python 3.10.x`, đầu dòng lệnh có `(.venv)`.

### 3.4. Tạo database (trong SSMS)

Mở SSMS, kết nối vào máy, chạy lần lượt (mỗi file bấm Execute):

1. `sql/00_setup/00_create_database.sql`
2. `sql/04_metadata/04_metadata_tables.sql`
3. `sql/02_staging/02_stg_taxi_zone.sql`
4. `sql/02_staging/02_stg_yellow_trip.sql`

### 3.5. Tải dữ liệu

```
python scripts/download_data.py
```

Mặc định tải tháng 2024-01 và 2025-01, kèm `taxi_zone_lookup.csv`. Tải thêm tháng khác: `python scripts/download_data.py --months 2024-01 2024-02 2025-01`. Nếu tải tự động lỗi, tải tay từ trang TLC Trip Record Data và đặt file vào `data/source/`.

### 3.6. Đặt biến môi trường

Trong PowerShell (**mỗi lần mở cửa sổ mới đều phải đặt lại**):

```
$env:DB_SERVER="localhost"                  # nếu cài Express: localhost\SQLEXPRESS
$env:DATA_DIR="C:\dw-taxi\data\source"      # đường dẫn tuyệt đối tới data/source
```

Nếu SQL Server của bạn dùng tài khoản SQL (không dùng Windows Authentication), thêm `$env:DB_USER` và `$env:DB_PASSWORD`. Nếu báo không tìm thấy driver, thêm `$env:DB_DRIVER="ODBC Driver 17 for SQL Server"`.

Kiểm tra kết nối:

```
python mage_extras/etl_common.py
```

Phải thấy dòng `Ket noi OK`.

### 3.7. Chạy Mage

Trong **cùng cửa sổ PowerShell** đã bật môi trường ảo và đặt biến:

```
mage start mage_etl --port 6790
```

Mở http://localhost:6790. Góc trên trái phải hiện `mage_etl`. Nếu trang yêu cầu đăng nhập, dùng `admin@admin.com` và mật khẩu `admin`.

## 4. Pipeline hiện có

| Pipeline | Làm gì | Người phụ trách | Trạng thái |
|---|---|---|---|
| `load_taxi_zones` | Nạp 265 khu vực vào `stg.taxi_zone` | Hảo | Xong |
| `load_yellow_trip` | Parquet → `stg.yellow_trip` & `stg.yellow_trip_reject` | Hiệu | Xong |
| Nạp Dim và Fact | Staging → `dds.*` | Cường | Xong |
| Pipeline tổng | Chạy tuần tự các bước trên theo tháng | Huy | Chưa làm |

Cập nhật bảng này khi hoàn thành.

**Việc đầu tiên của mỗi người sau khi cài xong:** chạy pipeline `load_taxi_zones` (mở pipeline trong Mage, chạy từng block hoặc bấm Run pipeline), rồi kiểm tra trong SSMS: `SELECT COUNT(*) FROM stg.taxi_zone` phải ra **265**. Cường cần bảng này để làm `dds.dim_location`.

## 5. Ai làm gì

| Người | Việc | Hạn | Cần có trước |
|---|---|---|---|
| **Hảo** | Môi trường, Metadata, nạp Zones (xong); đối soát và kiểm thử; tích hợp, ghép báo cáo, đóng gói nộp | 16–18/11 | Hiệu và Cường nạp xong |
| **Hiệu** | Bảng `stg.yellow_trip` và `stg.yellow_trip_reject`; pipeline nạp Parquet → Staging; làm sạch theo quy tắc mục I.4; viết phần báo cáo | 15–17/11 | Mapping của Huy |
| **Huy** | Mapping nguồn → Staging → DDS (`docs/mapping.xlsx`); test case; pipeline tổng và lịch chạy; viết phần báo cáo | 15–17/11 | Pipeline của Hiệu, Cường |
| **Cường** | Bảng DDS (Dim, Fact); nạp Dim; nạp `dds.fact_trip`; viết phần báo cáo | 15–17/11 | Mapping của Huy, `stg.taxi_zone`, Staging của Hiệu |

Mốc chung: **18/11 buổi trưa khóa code**, tối 18/11 nộp, 19/11 là ngày dự phòng.

## 6. Quy ước

### Tên bảng và cột

- Tên bảng: `stg.taxi_zone`, `stg.yellow_trip`, `stg.yellow_trip_reject`, `dds.dim_*`, `dds.fact_trip` (nếu đổi thì sửa trong `docs/mapping.xlsx` và báo cả nhóm).
- Tên cột `snake_case`, ví dụ `pickup_datetime`, `pu_location_id`, `total_amount`.
- Mỗi bảng Staging có cột `batch_id` (tham chiếu `meta.etl_batch`) để truy vết lần nạp.

### Ghi Metadata khi viết pipeline mới

Dùng các hàm trong `mage_etl/utils/etl_common.py`, theo mẫu `mage_blocks/load_taxi_zones/3_export_stg_taxi_zone.py`:

```python
from mage_etl.utils.etl_common import get_engine, start_batch, end_batch, log_error
# batch_id = start_batch(engine, 'ten_pipeline', 'Staging', 'stg.yellow_trip', period_key='2024-01')
# ... nạp dữ liệu ...
# end_batch(engine, batch_id, 'Success', rows_read=..., rows_loaded=..., rows_rejected=...)
# nếu lỗi: log_error(engine, batch_id, 'ten_buoc', e); end_batch(engine, batch_id, 'Failed', message=str(e)); raise
```

Hàm `is_period_loaded` và `mark_period_loaded` giúp bỏ qua tháng đã nạp thành công.

### Làm việc với Git

- Không làm trực tiếp trên `main`. Mỗi việc một nhánh: `feature/<tên>-<việc>` (ví dụ `feature/hieu-staging-trip`).
- Quy trình:

  ```
  git checkout main
  git pull origin main
  git checkout -b feature/hieu-staging-trip
  # ... làm việc ...
  git add .
  git commit -m "stg: nap yellow_trip 2024-01"
  git push -u origin feature/hieu-staging-trip
  ```

  Rồi mở **Pull Request** trên GitHub; một bạn khác xem rồi merge vào `main`.
- Mỗi người chỉ sửa **file/pipeline của mình**, để tránh xung đột.
- **Không commit:** dữ liệu (`*.parquet`, `*.csv` lớn), `.venv`, `*.pbix`, thư mục `mage_etl/mage_data/` và mật khẩu.
- Làm xong một pipeline thì commit **cả thư mục pipeline và block** của nó trong `mage_etl/` (`pipelines/`, `data_loaders/`, `transformers/`, `data_exporters/`).

## 7. Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân và cách sửa |
|---|---|
| `Failed to build 'Pillow'` khi `pip install` | Đang dùng Python 3.13 hoặc 3.14. Tạo môi trường ảo bằng Python 3.10 (mục 3.3) |
| `SyntaxError: (unicode error) 'unicodeescape'` trong Mage | Repo nằm ở đường dẫn dài có `\U`, `\n`. Chuyển sang `C:\dw-taxi` và tạo lại `.venv` |
| Mage mở ra project khác (ví dụ `adventureworks_bi`) | Cổng bị chiếm bởi Mage cũ. Tắt nó, hoặc dùng `--port 6790` |
| `Data source name not found` | Sai tên driver. Đặt `$env:DB_DRIVER="ODBC Driver 17 for SQL Server"` (hoặc 18) rồi chạy lại Mage |
| `Login failed` | Sai kiểu đăng nhập SQL Server. Không đặt `DB_USER` thì dùng Windows Authentication |
| `Invalid object name 'stg...'` hoặc `'meta...'` | Chưa chạy các script SQL ở mục 3.4 |
| `FileNotFoundError ... taxi_zone_lookup.csv` | Chưa đặt `DATA_DIR` hoặc sai đường dẫn; đặt lại rồi **khởi động lại Mage** |
| `ModuleNotFoundError: mage_etl.utils` | Chạy `mage start mage_etl` từ **thư mục gốc repo**; kiểm tra `mage_etl/utils/etl_common.py` có tồn tại |
| Biến môi trường không có tác dụng | Đặt biến **trước** khi chạy `mage start`, trong cùng cửa sổ PowerShell |

## 8. Kiểm thử

Sau khi các tầng nạp xong, chạy `sql/05_tests/05_reconcile_checks.sql` trong SSMS để đối soát số dòng và tổng tiền giữa các tầng. Mỗi dòng kết quả là PASS hoặc FAIL. Tên bảng và cột trong script là tên giả định (`stg.yellow_trip`, `dds.fact_trip`, `total_amount`), cần sửa cho khớp với mapping thật.

## 9. Đóng gói nộp (Src)

```
git archive --format=zip -o MaNhom_Src.zip HEAD
```

Lệnh này chỉ đóng gói các tệp đã commit nên không kèm dữ liệu. Sau đó gói `MaNhom_BaoCao.pdf` và `MaNhom_Src.zip` vào một file zip tên `MaNhom_MSSV1_MSSV2_MSSV3_MSSV4.zip` rồi nộp lên Moodle.

## 10. Tài liệu triển khai tầng Staging và Làm sạch dữ liệu (Hiệu)

### 10.1. Thiết kế bảng Staging (`sql/02_staging/02_stg_yellow_trip.sql`)

- **`stg.yellow_trip`**: Chứa các bản ghi hợp lệ sau khi làm sạch.
  - Tên cột chuẩn hóa đồng nhất theo `snake_case` cho tất cả các năm (`vendor_id`, `pickup_datetime`, `total_amount`,...).
  - Tối ưu dung lượng kiểu số thực tiền tệ: Sử dụng `DECIMAL(10,2)` thay vì `DECIMAL(18,2)`, tiết kiệm 44 bytes trên từng dòng dữ liệu (tiết kiệm hàng trăm MB đĩa và RAM khi nạp hàng triệu dòng).
  - Tương thích đa năm (Schema Evolution): Các cột phụ phí mới ở các năm sau (`congestion_surcharge`, `airport_fee`, `cbd_congestion_fee`) được gán giá trị mặc định `0.0` để khi nạp các năm cũ (như 2015, 2024) không bị lỗi thiếu cột.
  - Bổ sung khóa chính tự tăng `stg_trip_id BIGINT IDENTITY(1,1)` và non-clustered index trên `(batch_id)`, `(pickup_datetime)` để tối ưu hiệu năng truy vấn và đối soát.
- **`stg.yellow_trip_reject`**: Chứa toàn bộ các bản ghi vi phạm quy tắc làm sạch.
  - Cấu trúc tương tự bảng chính nhưng bổ sung cột `reject_reason VARCHAR(255)` để lưu chi tiết các mã lỗi vi phạm và `rejected_at` phục vụ kiểm toán dữ liệu.

### 10.2. Quy tắc làm sạch dữ liệu (Mục I.4 & Quyết định G9)

Các bản ghi vi phạm một trong các điều kiện sau sẽ được tự động chuyển sang bảng `stg.yellow_trip_reject`:

| Mã lỗi (`reject_reason`) | Điều kiện vi phạm | Ý nghĩa nghiệp vụ |
|---|---|---|
| `DROPOFF_LE_PICKUP` | `dropoff_datetime <= pickup_datetime` | Thời điểm trả trước hoặc bằng thời điểm đón |
| `DURATION_EXCEEDS_24H` | `(dropoff - pickup) > 24 giờ` | Thời lượng chuyến đi kéo dài bất thường |
| `DISTANCE_LE_ZERO` | `trip_distance <= 0` hoặc `NULL` | Quãng đường di chuyển bằng 0 hoặc âm |
| `NEGATIVE_FARE` | `fare_amount < 0` | Tiền cước bị âm (giao dịch hoàn tiền hoặc lỗi hệ thống) |
| `INVALID_TOTAL_AMOUNT` | `total_amount < 0` hoặc `> 1000` | Tổng tiền âm hoặc vượt quá ngưỡng hợp lý (1.000 USD) |
| `OUT_OF_PERIOD` | `pickup_datetime` ngoài tháng nạp | Bản ghi lạc kỳ (ví dụ file 2024-01 nhưng thời gian đón ở 2023) |
| `INVALID_DATETIME` | `pickup_datetime` hoặc `dropoff_datetime` bị `NULL` | Không thể xác định mốc thời gian của chuyến đi |

*Lưu ý:* Nếu một dòng vi phạm nhiều lỗi đồng thời, các mã lỗi sẽ được kết hợp bằng dấu `;` (ví dụ: `DISTANCE_LE_ZERO;NEGATIVE_FARE`).

### 10.3. Pipeline nạp Trip (`mage_etl/pipelines/load_yellow_trip`)

- **Đọc theo khối (Streaming Chunking)**: Sử dụng `pyarrow.parquet.ParquetFile.iter_batches(batch_size=100_000)` để streaming từng khối 100.000 dòng. Bộ nhớ RAM luôn duy trì ổn định dưới 150 MB trong suốt quá trình nạp file gần 3 triệu dòng, tránh nguy cơ tràn RAM.
- **Tính Idempotent**: Kiểm tra `is_period_loaded(engine, 'yellow_trip', period_key)`. Nếu tháng đó đã có trạng thái `Success` trong `meta.etl_load_control`, pipeline sẽ tự động in thông báo và bỏ qua, không nạp trùng lặp.
- **Ghi vết Metadata**: Khởi tạo batch bằng `start_batch()`, ghi nhận `rows_read`, `rows_loaded`, `rows_rejected` qua `end_batch()`, và lưu lỗi vào `meta.etl_error_log` qua `log_error()`.

### 10.4. Cách chạy và Kiểm tra đối soát

1. **Chạy nạp dữ liệu**:
   ```powershell
   # Cách 1: Chạy trực tiếp qua script (khuyên dùng, có thanh tiến độ trực quan)
   python scripts/load_yellow_trip.py

   # Cách 2: Chạy qua Mage CLI
   mage run mage_etl load_yellow_trip
   ```

2. **Kiểm tra đối soát và lấy số liệu báo cáo**:
   - Chạy `sql/05_tests/05_reconcile_checks.sql`: Kiểm tra Check 3 (`rows_read = rows_loaded + rows_rejected`) và Check 4 (`stg.yellow_trip rows = sum(rows_loaded)`) đạt `PASS`.
   - Chạy `sql/05_tests/06_reject_statistics.sql`: Xuất 4 bảng thống kê chi tiết về số lượng nạp, số lượng reject, và phân rã các lý do lỗi phục vụ viết báo cáo.

