-- 05_reconcile_checks.sql
-- Cac kiem tra doi soat co ban. Moi dong ket qua la PASS hoac FAIL.
-- Chay sau khi cac pipeline da nap xong. Kiem tra nao thieu bang se tu bo qua.
-- LUU Y: ten bang/cot stg.yellow_trip, dds.fact_trip, total_amount la ten gia dinh;
--        sua lai cho khop voi ten that nhom da chot trong file mapping.

USE NYCTaxi_DW;
GO
SET NOCOUNT ON;

DECLARE @r TABLE (check_name NVARCHAR(200), expected NVARCHAR(100), actual NVARCHAR(100), result NVARCHAR(10));

-- 1. Danh muc zone co du 265 dong
IF OBJECT_ID(N'stg.taxi_zone') IS NOT NULL
    INSERT @r
    SELECT N'stg.taxi_zone has 265 zones', N'265', CAST(COUNT(*) AS NVARCHAR(100)),
           CASE WHEN COUNT(*) = 265 THEN N'PASS' ELSE N'FAIL' END
    FROM stg.taxi_zone;

-- 2. Khong co batch nao bi Failed
IF OBJECT_ID(N'meta.etl_batch') IS NOT NULL
    INSERT @r
    SELECT N'no failed ETL batches', N'0', CAST(COUNT(*) AS NVARCHAR(100)),
           CASE WHEN COUNT(*) = 0 THEN N'PASS' ELSE N'FAIL' END
    FROM meta.etl_batch WHERE status = N'Failed';

-- 3. Staging: rows_read = rows_loaded + rows_rejected o moi batch thanh cong
IF OBJECT_ID(N'meta.etl_batch') IS NOT NULL
    INSERT @r
    SELECT N'staging batches: read = loaded + rejected', N'0 bad batches', CAST(COUNT(*) AS NVARCHAR(100)) + N' bad batches',
           CASE WHEN COUNT(*) = 0 THEN N'PASS' ELSE N'FAIL' END
    FROM meta.etl_batch
    WHERE layer = N'Staging' AND status = N'Success'
      AND rows_read IS NOT NULL
      AND rows_read <> ISNULL(rows_loaded, 0) + ISNULL(rows_rejected, 0);

-- 4. So dong stg.yellow_trip khop tong rows_loaded trong log
IF OBJECT_ID(N'stg.yellow_trip') IS NOT NULL
    INSERT @r
    SELECT N'stg.yellow_trip rows = sum(rows_loaded) in log',
           CAST((SELECT ISNULL(SUM(rows_loaded), 0) FROM meta.etl_batch
                 WHERE target_table = N'stg.yellow_trip' AND status = N'Success') AS NVARCHAR(100)),
           CAST((SELECT COUNT_BIG(*) FROM stg.yellow_trip) AS NVARCHAR(100)),
           CASE WHEN (SELECT COUNT_BIG(*) FROM stg.yellow_trip) =
                     (SELECT ISNULL(SUM(rows_loaded), 0) FROM meta.etl_batch
                      WHERE target_table = N'stg.yellow_trip' AND status = N'Success')
                THEN N'PASS' ELSE N'FAIL' END;

-- 5. DDS: so dong fact_trip bang so dong staging (neu dong loi da duoc tach o Staging)
IF OBJECT_ID(N'stg.yellow_trip') IS NOT NULL AND OBJECT_ID(N'dds.fact_trip') IS NOT NULL
    INSERT @r
    SELECT N'dds.fact_trip rows = stg.yellow_trip rows',
           CAST((SELECT COUNT_BIG(*) FROM stg.yellow_trip) AS NVARCHAR(100)),
           CAST((SELECT COUNT_BIG(*) FROM dds.fact_trip) AS NVARCHAR(100)),
           CASE WHEN (SELECT COUNT_BIG(*) FROM stg.yellow_trip) = (SELECT COUNT_BIG(*) FROM dds.fact_trip)
                THEN N'PASS' ELSE N'FAIL' END;

-- 6. Tong tien khop giua Staging va DDS (chinh ten cot neu khac)
IF OBJECT_ID(N'stg.yellow_trip') IS NOT NULL AND OBJECT_ID(N'dds.fact_trip') IS NOT NULL
    INSERT @r
    SELECT N'sum(total_amount) stg = fact',
           CAST((SELECT ROUND(SUM(CAST(total_amount AS DECIMAL(18,2))), 2) FROM stg.yellow_trip) AS NVARCHAR(100)),
           CAST((SELECT ROUND(SUM(CAST(total_amount AS DECIMAL(18,2))), 2) FROM dds.fact_trip) AS NVARCHAR(100)),
           CASE WHEN (SELECT ROUND(SUM(CAST(total_amount AS DECIMAL(18,2))), 2) FROM stg.yellow_trip) =
                     (SELECT ROUND(SUM(CAST(total_amount AS DECIMAL(18,2))), 2) FROM dds.fact_trip)
                THEN N'PASS' ELSE N'FAIL' END;

-- 7. GĐ1: 8 dimension trong DDS da nap day du
IF OBJECT_ID(N'dds.dim_date') IS NOT NULL
    INSERT @r
    SELECT N'8 DDS dimensions populated', N'8', CAST((
        SELECT COUNT(*) FROM (
            SELECT COUNT(*) AS c, 1 AS minc FROM dds.dim_date
            UNION ALL SELECT COUNT(*), 1440 FROM dds.dim_time
            UNION ALL SELECT COUNT(*), 266 FROM dds.dim_location
            UNION ALL SELECT COUNT(*), 5 FROM dds.dim_vendor
            UNION ALL SELECT COUNT(*), 8 FROM dds.dim_payment_type
            UNION ALL SELECT COUNT(*), 8 FROM dds.dim_rate_code
            UNION ALL SELECT COUNT(*), 4 FROM dds.dim_passenger_group
            UNION ALL SELECT COUNT(*), 6 FROM dds.dim_distance_band) x WHERE x.c >= x.minc) AS NVARCHAR(100)),
           CASE WHEN (SELECT COUNT(*) FROM (
                SELECT COUNT(*) AS c, 1 AS minc FROM dds.dim_date
                UNION ALL SELECT COUNT(*), 1440 FROM dds.dim_time
                UNION ALL SELECT COUNT(*), 266 FROM dds.dim_location
                UNION ALL SELECT COUNT(*), 5 FROM dds.dim_vendor
                UNION ALL SELECT COUNT(*), 8 FROM dds.dim_payment_type
                UNION ALL SELECT COUNT(*), 8 FROM dds.dim_rate_code
                UNION ALL SELECT COUNT(*), 4 FROM dds.dim_passenger_group
                UNION ALL SELECT COUNT(*), 6 FROM dds.dim_distance_band) x WHERE x.c >= x.minc) = 8
            THEN N'PASS' ELSE N'FAIL' END;

-- 8. GĐ1: moi dong fact phai co day du 11 khoa ngoai + measure
IF OBJECT_ID(N'dds.fact_trip') IS NOT NULL
    INSERT @r
    SELECT N'fact rows with NULL or orphan dimension keys',
           N'0', CAST(COUNT_BIG(*) AS NVARCHAR(100)),
           CASE WHEN COUNT_BIG(*) = 0 THEN N'PASS' ELSE N'FAIL' END
    FROM dds.fact_trip f
    LEFT JOIN dds.dim_date dd ON dd.date_key = f.date_key
    LEFT JOIN dds.dim_time tp ON tp.time_key = f.pickup_time_key
    LEFT JOIN dds.dim_time tq ON tq.time_key = f.dropoff_time_key
    LEFT JOIN dds.dim_location pl ON pl.location_key = f.pu_location_key
    LEFT JOIN dds.dim_location dl ON dl.location_key = f.do_location_key
    LEFT JOIN dds.dim_vendor v ON v.vendor_key = f.vendor_key
    LEFT JOIN dds.dim_payment_type pay ON pay.payment_key = f.payment_key
    LEFT JOIN dds.dim_rate_code rc ON rc.rate_code_key = f.rate_code_key
    LEFT JOIN dds.dim_passenger_group pg ON pg.passenger_group_key = f.passenger_group_key
    LEFT JOIN dds.dim_distance_band db ON db.distance_band_key = f.distance_band_key
    WHERE dd.date_key IS NULL OR tp.time_key IS NULL OR tq.time_key IS NULL
       OR pl.location_key IS NULL OR dl.location_key IS NULL OR v.vendor_key IS NULL
       OR pay.payment_key IS NULL OR rc.rate_code_key IS NULL OR pg.passenger_group_key IS NULL
       OR db.distance_band_key IS NULL OR f.trip_count <> 1 OR f.trip_duration IS NULL;

SELECT * FROM @r ORDER BY check_name;
GO
SELECT COUNT(*) FROM stg.taxi_zone