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

SELECT * FROM @r ORDER BY check_name;
GO
SELECT COUNT(*) FROM stg.taxi_zone