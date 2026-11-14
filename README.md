# NYC Yellow Taxi Data Warehouse (CSC12107 – Giai đoạn 2)

Kiến trúc 3 tầng: **Source → Staging → DDS**, công cụ: **SQL Server + Mage AI** (Power BI, SSAS dùng ở giai đoạn 3).

| Tầng | Là gì | Nằm ở đâu |
|---|---|---|
| Source | Tệp nguồn: Yellow Taxi Trip (Parquet), Taxi Zones (CSV), Shapefile | `data/source/` (không đưa lên GitHub) |
| Staging | Dữ liệu đã nạp vào SQL Server, chuẩn hóa tên/kiểu, làm sạch | schema `stg` trong database `NYCTaxi_DW` |
| DDS | Kho đa chiều: Dim và Fact | schema `dds` |
| Metadata | Log ETL, lỗi, trạng thái nạp theo tháng, từ điển dữ liệu | schema `meta` |

## Cấu trúc thư mục

```
sql/00_setup      tạo database và schema
sql/02_staging    bảng Staging
sql/03_dds        bảng Dim, Fact
sql/04_metadata   bảng Metadata
sql/05_tests      script kiểm thử, đối soát
mage_etl/         project Mage (tạo bằng `mage init mage_etl`)
mage_extras/      hàm dùng chung (copy vào mage_etl/utils/)
mage_blocks/      mã các block Mage để dán vào pipeline
scripts/          tải dữ liệu
docs/             báo cáo, mapping, sơ đồ
```

## Cài đặt (làm một lần)

1. Cài SQL Server (Developer hoặc Express), SSMS, **ODBC Driver 18 for SQL Server**, Python 3.10 hoặc 3.11.
2. `pip install -r requirements.txt`
3. Mở SSMS, chạy lần lượt: `sql/00_setup/00_create_database.sql`, `sql/04_metadata/04_metadata_tables.sql`, `sql/02_staging/02_stg_taxi_zone.sql`.
4. Tải dữ liệu: `python scripts/download_data.py` (hoặc tải tay vào `data/source/`).
5. Đặt biến môi trường (PowerShell), ví dụ:
   ```
   $env:DB_SERVER="localhost"          # hoặc localhost\SQLEXPRESS
   $env:DATA_DIR="D:\nyc-taxi-dw\data\source"
   ```
   Dùng SQL login thì thêm `DB_USER`, `DB_PASSWORD`. Không đặt thì dùng Windows Authentication.
6. Kiểm tra kết nối: `python mage_extras/etl_common.py`
7. `mage init mage_etl`, rồi copy `mage_extras/etl_common.py` vào `mage_etl/utils/etl_common.py`.
8. Chạy Mage **trong cùng cửa sổ PowerShell đã đặt biến môi trường**: `mage start mage_etl` → mở http://localhost:6789.

## Chạy pipeline

- `load_taxi_zones`: nạp 265 khu vực vào `stg.taxi_zone` (xem `mage_blocks/load_taxi_zones/`).
- Các pipeline khác: thêm vào bảng này khi làm xong.

## Quy ước làm việc

- Mỗi người một nhánh: `feature/<tên>-<việc>`; xong thì mở Pull Request, một bạn khác xem rồi merge vào `main`.
- Không commit dữ liệu (`*.parquet`, `*.csv` lớn, `*.pbix`).
- Tên bảng: `stg.yellow_trip`, `stg.taxi_zone`, `dds.dim_*`, `dds.fact_trip` (chỉnh theo file mapping của nhóm).

## Đóng gói nộp (Src)

```
git archive --format=zip -o MaNhom_Src.zip HEAD
```
Lệnh này chỉ đóng gói các tệp đã commit nên không kèm dữ liệu.
