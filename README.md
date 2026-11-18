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
scripts/           tải dữ liệu, chạy Master ETL
tests/             unit test Python của Master ETL
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
5. `sql/03_dds/03_dds_tables.sql`

### 3.5. Tải dữ liệu

```
python scripts/download_data.py
```

Mặc định tải tháng 2024-01 và 2025-01, kèm `taxi_zone_lookup.csv`. Tải thêm tháng khác: `python scripts/download_data.py --months 2024-01 2024-02 2025-01`. Nếu tải tự động lỗi, tải tay từ trang TLC Trip Record Data và đặt file vào `data/source/`.

### 3.6. Đặt biến môi trường

Trong PowerShell (**mỗi lần mở cửa sổ mới đều phải đặt lại**):

```
$env:DB_SERVER="localhost\SQLEXPRESS"                  # nếu cài Express: localhost\SQLEXPRESS
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
| Nạp Dim và Fact | Staging → `dds.*` | Cường | Xong — **8 Dimension + `dds.fact_trip`** theo GĐ1 (11 khoá ngoại, đủ measure) |
| `master_etl` | Zones → Staging → Dim → Fact → đối soát | Huy | Đã tích hợp; kiểm thử ba kỳ và Scheduler thành công |

Cập nhật bảng này khi hoàn thành.

**Nếu kiểm thử riêng pipeline thành phần:** chạy pipeline `load_taxi_zones` (mở pipeline trong Mage, chạy từng block hoặc bấm Run pipeline), rồi kiểm tra trong SSMS: `SELECT COUNT(*) FROM stg.taxi_zone` phải ra **265**. Cường cần bảng này để làm `dds.dim_location`. Nếu chạy master ở mục 11 thì không cần chạy riêng từng pipeline trước; không chạy đồng thời master và pipeline thành phần.

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
- Ưu tiên sửa file/pipeline của mình. Nếu tích hợp cần chỉnh code của thành viên khác, ghi rõ thay đổi trong Pull Request và yêu cầu người phụ trách review trước khi merge. Nhánh tích hợp của Huy: `feature/huy-master-etl`.
- **Không commit:** dữ liệu (`*.parquet`, `*.csv` lớn), `.venv`, `*.pbix`, thư mục `mage_etl/mage_data/` và mật khẩu.
- Làm xong một pipeline thì commit **cả thư mục pipeline và block** của nó trong `mage_etl/` (`pipelines/`, `data_loaders/`, `transformers/`, `data_exporters/`).

## 7. Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân và cách sửa |
|---|---|
| `Failed to build 'Pillow'` khi `pip install` | Đang dùng Python 3.13 hoặc 3.14. Tạo môi trường ảo bằng Python 3.10 (mục 3.3) |
| `SyntaxError: (unicode error) 'unicodeescape'` trong Mage | Repo nằm ở đường dẫn dài có `\U`, `\n`. Chuyển sang `C:\dw-taxi` và tạo lại `.venv` |
| Mage mở ra project khác (ví dụ `adventureworks_bi`) | Cổng bị chiếm bởi Mage cũ. Tắt nó, hoặc dùng `--port 6790` |
| `Data source name not found` | Sai tên driver. Đặt `$env:DB_DRIVER="ODBC Driver 17 for SQL Server"` (hoặc 18) rồi chạy lại Mage |
| `Login failed` / 4060 | Kiểm tra đúng instance, Windows Authentication hoặc tài khoản SQL; kiểm tra database `NYCTaxi_DW` đã tồn tại và tài khoản có quyền truy cập |
| `Test-Path` báo Path null | Biến DATA_DIR chưa được đặt trong phiên PowerShell hiện tại; đặt lại đường dẫn tuyệt đối |
| Scheduler Failed sau Edit trigger | Kiểm tra runtime variable `period_key=auto`; lưu lại cấu hình và dùng mặc định auto trong block master |
| `Invalid object name 'stg...'` hoặc `'meta...'` | Chưa chạy các script SQL ở mục 3.4 |
| `FileNotFoundError ... taxi_zone_lookup.csv` | Chưa đặt `DATA_DIR` hoặc sai đường dẫn; đặt lại rồi **khởi động lại Mage** |
| `ModuleNotFoundError: mage_etl.utils` | Chạy `mage start mage_etl` từ **thư mục gốc repo**; kiểm tra `mage_etl/utils/etl_common.py` có tồn tại |
| Biến môi trường không có tác dụng | Đặt biến **trước** khi chạy `mage start`, trong cùng cửa sổ PowerShell |

## 8. Kiểm thử

Sau khi các tầng nạp xong, chạy `sql/05_tests/05_reconcile_checks.sql` trong SSMS để đối soát số dòng và tổng tiền giữa các tầng. Mỗi dòng kết quả là PASS hoặc FAIL. Kiểm tra script đối soát chung theo schema thực tế; với Master ETL dùng thêm `sql/05_tests/08_master_period_checks.sql` theo từng kỳ (mục 11). Không sửa script chỉ để ép kết quả PASS.

## 9. Đóng gói nộp (Src)

```
git archive --format=zip -o MaNhom_Src.zip HEAD
```

Lệnh này chỉ đóng gói các tệp đã commit nên không kèm dữ liệu. Sau đó gói `MaNhom_BaoCao.pdf` và `MaNhom_Src.zip` vào một file zip tên `MaNhom_MSSV1_MSSV2_MSSV3_MSSV4.zip` rồi nộp lên Moodle.

## 10. Tài liệu triển khai tầng Staging và Làm sạch dữ liệu (Hiệu)

### 10.1. Thiết kế bảng Staging (`sql/02_staging/02_stg_yellow_trip.sql`)

- **`stg.yellow_trip`**: Chứa các bản ghi hợp lệ sau khi làm sạch.
  - Tên cột chuẩn hóa đồng nhất theo `snake_case` cho tất cả các năm (`vendor_id`, `pickup_datetime`, `total_amount`,...).
  - Kiểu số thực tiền tệ: Sử dụng `DECIMAL(10,2)` thay vì `DECIMAL(18,2)`, cùng dung lượng 9 bytes/cột như DECIMAL(18,2); không tiết kiệm 44 bytes/dòng.
  - Tương thích đa năm (Schema Evolution): Các cột phụ phí mới ở các năm sau (`congestion_surcharge`, `airport_fee`, `cbd_congestion_fee`) được gán giá trị mặc định `0.0` để khi nạp các năm cũ (như 2015, 2024) không bị lỗi thiếu cột.
  - Bổ sung khóa chính tự tăng `stg_trip_id BIGINT IDENTITY(1,1)` và non-clustered index trên `(batch_id)`, `(pickup_datetime)` để tối ưu hiệu năng truy vấn và đối soát.
- **`stg.yellow_trip_reject`**: Chứa toàn bộ các bản ghi vi phạm quy tắc làm sạch.
  - Cấu trúc tương tự bảng chính nhưng bổ sung cột `reject_reason VARCHAR(255)` để lưu chi tiết các mã lỗi vi phạm và `rejected_at` phục vụ kiểm toán dữ liệu.

### 10.2. Quy tắc làm sạch dữ liệu (Mục I.4 & Quyết định G9)

Theo code hiện tại, các bản ghi vi phạm một trong các điều kiện sau sẽ được tự động chuyển sang bảng `stg.yellow_trip_reject`:

| Mã lỗi (`reject_reason`) | Điều kiện vi phạm | Ý nghĩa nghiệp vụ |
|---|---|---|
| `DROPOFF_LE_PICKUP` | `dropoff_datetime <= pickup_datetime` | Thời điểm trả trước hoặc bằng thời điểm đón |
| `DURATION_EXCEEDS_24H` | `(dropoff - pickup) > 24 giờ` | Thời lượng chuyến đi kéo dài bất thường |
| `DISTANCE_LE_ZERO` | `trip_distance <= 0` hoặc `NULL` | Quãng đường di chuyển bằng 0 hoặc âm |
| `NEGATIVE_FARE` | `fare_amount < 0` | Tiền cước bị âm (giao dịch hoàn tiền hoặc lỗi hệ thống) |
| `INVALID_TOTAL_AMOUNT` | `total_amount < 0` hoặc `> 1000` | Tổng tiền âm hoặc vượt quá ngưỡng hợp lý (1.000 USD) |
| `OUT_OF_PERIOD` | `pickup_datetime` ngoài tháng nạp | Bản ghi lạc kỳ (ví dụ file 2024-01 nhưng thời gian đón ở 2023) |
| `INVALID_DATETIME` | `pickup_datetime` hoặc `dropoff_datetime` bị `NULL` | Không thể xác định mốc thời gian của chuyến đi |

*Lưu ý:* Quy tắc `DISTANCE_LE_ZERO` khác GĐ1 (giữ chuyến và gán Invalid); chưa khử trùng nghiệp vụ hoàn toàn theo G9. Xem `docs/Doi_chieu_GD1_repo.md`. Nếu một dòng vi phạm nhiều lỗi đồng thời, các mã lỗi sẽ được kết hợp bằng dấu `;` (ví dụ: `DISTANCE_LE_ZERO;NEGATIVE_FARE`).

### 10.3. Pipeline nạp Trip (`mage_etl/pipelines/load_yellow_trip`)

- **Đọc theo khối (Streaming Chunking)**: Sử dụng `pyarrow.parquet.ParquetFile.iter_batches(batch_size=100_000)` để streaming từng khối 100.000 dòng. Cách đọc này giúp giảm áp lực RAM; mức sử dụng thực tế phụ thuộc môi trường và dữ liệu.
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


## 11. Vận hành Master ETL (tích hợp chung)

### 11.1. Phạm vi và điều kiện

Master điều phối Zones → Trip Staging/Reject → Dim Location → Fact → đối soát. Dim Date và 7 Dimension còn lại được tạo bằng SQL trước khi chạy (lịch 2015–2026; `sql/03_dds/03_dds_tables.sql` tạo đủ **8 Dimension + Fact** theo GĐ1, idempotent nên chạy lại nhiều lần được). Phạm vi ưu tiên là file có PU/DO LocationID từ khoảng 2015; mới kiểm thử thực tế ba kỳ 2024-01, 2024-02, 2025-01.

Trước khi chạy, hoàn thành mục 3, kiểm tra `Ket noi OK`, đủ các bảng và file nguồn. Ví dụ đặt đường dẫn theo repo hiện tại:

```powershell
$env:DATA_DIR = (Resolve-Path .\data\source).Path
# DB_SERVER phải trùng Server name thực tế trong SSMS
$env:DB_SERVER = "localhost\SQLEXPRESS"
# Nếu máy chỉ có Driver 17:
$env:DB_DRIVER = "ODBC Driver 17 for SQL Server"
python mage_extras/etl_common.py
```

SQL Server Express giới hạn 10 GB file dữ liệu mỗi database (không tính log). Kiểm tra dung lượng file dữ liệu và ổ đĩa trước khi nạp thêm, đặc biệt sau khi đã nạp ba tháng:

```sql
USE NYCTaxi_DW;
SELECT name, type_desc, size * 8.0 / 1024 AS SizeMB,
       CASE WHEN type_desc = 'ROWS' THEN FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 END AS UsedMB
FROM sys.database_files;
```

Tổng dung lượng file `ROWS` không được vượt 10.240 MB trên Express; còn phải tính không gian cho dữ liệu, index và tăng trưởng file, kiểm tra ổ đĩa cho log. Dùng SQL Server Developer cho môi trường học tập/kiểm thử nếu cần kho lớn hơn. Không DROP hoặc shrink database để chạy demo.

### 11.2. Chạy bằng PowerShell

```powershell
python -m unittest discover -s tests -v
python scripts/run_master_etl.py --months 2025-01
# Chạy lại để kiểm tra skip và đối soát
python scripts/run_master_etl.py --months 2025-01
# Mở rộng từng kỳ sau khi kiểm tra dung lượng
python scripts/run_master_etl.py --months 2024-01
python scripts/run_master_etl.py --months 2024-02
```

Master kiểm tra metadata và bỏ qua kỳ đã Success; không tự tải thêm file TLC. Không chạy song song pipeline thành phần khi master đang hoạt động. Không xóa log lịch sử để xử lý lỗi. Có thể chạy chế độ tự phát hiện kỳ chưa nạp bằng `python scripts/run_master_etl.py --auto`.

**Phạm vi mở rộng cho MR2 (chưa kiểm thử):** 2025-05 và 2025-06 nhằm chuẩn bị dữ liệu so sánh tháng 5–6 cùng năm. Không tính hai kỳ này vào kết quả 36/36 PASS của ba kỳ gốc. Nếu đủ dung lượng, tạm tắt lịch Mage và kiểm tra không có run đang chạy, sao chép từng file đã tải vào `DATA_DIR` (hoặc tải bằng `python scripts/download_data.py --months 2025-05`, sau đó tương tự cho 2025-06 nếu DATA_DIR là `data/source`). Chạy `python scripts/run_master_etl.py --auto` với file tháng 5 mới để kiểm thử TC20; chạy SQL 08 với `@k = '2025-05'`. Kiểm tra lại dung lượng trước khi bổ sung tháng 6 rồi chạy `python scripts/run_master_etl.py --months 2025-06` và SQL 08 cho tháng 6. Khôi phục lịch sau khi hoàn tất. Xem mục F của Test Plan. Không bắt buộc mở rộng dữ liệu trong môi trường Express nếu chưa đủ dung lượng; nhóm cần thống nhất phạm vi nộp và môi trường cho MR2.

### 11.3. Chạy bằng Mage và đặt lịch

Khởi động Mage từ thư mục gốc, cùng terminal đã đặt biến môi trường (mục 3.7). Mở `master_etl` → Triggers. Trigger `master_etl_manual`: Schedule, once, `period_key=2025-01`, Run@once. Trigger `master_etl_daily`:

| Thiết lập | Giá trị |
|---|---|
| Frequency | Custom: `0 19 * * *` |
| Múi giờ | UTC (02:00 sáng ngày hôm sau tại Việt Nam) |
| Runtime variable | `period_key=auto` |
| Skip run if previous run still in progress | true |
| Keep running pipeline even if blocks fail | false |

Save changes → kiểm tra biến → Enable trigger. Dùng Run@once để thử auto trên nguồn hiện có. Muốn kiểm thử Scheduler, tạm đặt `*/2 * * * *`, kiểm tra tự sinh run Done mà không nhấn Run@once; sau đó khôi phục cron chính thức, kiểm tra lại biến và nhấn **Update trigger in code** (hoặc Save trigger in code nếu chưa lưu). Kiểm tra Git diff để xác nhận cấu hình cuối. Giữ Mage và SQL Server hoạt động, máy không ngủ.

### 11.4. Kiểm thử và kết quả xác nhận

Chạy `sql/05_tests/08_master_period_checks.sql` trong SSMS hoặc VS Code SQL, đổi `DECLARE @k CHAR(7)` lần lượt sang ba kỳ. Kết quả thực nghiệm 17–18/11/2026:

| Kỳ | Source | Valid/Fact | Reject | Doanh thu USD | SQL 08 |
|---|---:|---:|---:|---:|---|
| 2024-01 | 2.964.624 | 2.869.967 | 94.657 | 78.474.541,40 | 12/12 PASS |
| 2024-02 | 3.007.526 | 2.901.778 | 105.748 | 79.036.753,37 | 12/12 PASS |
| 2025-01 | 3.475.226 | 3.253.069 | 222.157 | 87.235.063,20 | 12/12 PASS |
| **Tổng** | **9.447.376** | **9.024.814** | **422.562** | **244.746.357,97** | **36/36 PASS** |

Unit test 2/2 PASS; Mage manual Run ID 1 Done, auto Run ID 2 Done, Scheduler Run ID 5 Done sau khi sửa lỗi thiếu tham số. Đã kiểm tra cơ chế skip tháng 2025-01; cần bổ sung đối soát cuối toàn kho, kiểm thử retry, thiếu file, auto với tháng mới và các GAP GĐ1. Không coi 38 lượt SQL/unit test là 25/25 test case PASS.

Tài liệu: [Test Plan](docs/Test_Plan_Huy.md), [Báo cáo phần Huy](docs/BaoCao_Phan_Huy.md).
