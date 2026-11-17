-- 07_review_staging_yellow_trip.sql
-- Kiem tra cong viec nap Trip vao Staging (Hieu): stg.yellow_trip, stg.yellow_trip_reject.
-- Chay sau khi da nap thang 2024-01 (va 2025-01) bang pipeline load_yellow_trip.
-- GIA DINH ten cot (lay tu docstring cua code): pickup_datetime, dropoff_datetime, trip_distance,
--   fare_amount, total_amount, passenger_count, batch_id; bang reject co cot reject_reason.
-- Neu ten cot that khac, sua lai cho khop (xem muc I cua script: INFORMATION_SCHEMA).
-- Cac so ky vong lay tu ket qua profiling gd1 (bang 6 trong bao cao).

USE NYCTaxi_DW;
GO
SET NOCOUNT ON;

-- ===== I. Cau truc bang Staging (doc bang cot de kiem tra ten/kieu) =====
SELECT TABLE_NAME, ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'stg' AND TABLE_NAME IN (N'yellow_trip', N'yellow_trip_reject')
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- ===== A. Nhat ky nap (moi thang mot hoac nhieu batch) =====
SELECT batch_id, pipeline_name, period_key, status, rows_read, rows_loaded, rows_rejected,
       start_time, end_time, LEFT(message, 200) AS message
FROM meta.etl_batch
WHERE pipeline_name LIKE N'%yellow%'
ORDER BY batch_id DESC;

-- ===== B. Doi chieu voi so lieu profiling (batch thanh cong moi nhat cua tung thang) =====
-- read_equals_file : so dong doc = so dong trong tep Parquet (2024-01: 2,964,624; 2025-01: 3,475,226)
-- balanced         : read = loaded + rejected
-- rejects_ge_min   : so dong bi loai phai >= so dong vi pham quy tac lon nhat
--                    (2024-01: trip_distance <= 0 = 60,371; 2025-01: fare_amount < 0 = 144,118)
;WITH exp AS (
    SELECT * FROM (VALUES (N'2024-01', 2964624, 60371),
                          (N'2025-01', 3475226, 144118)) v(period_key, total_rows, min_rejects)
), b AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY period_key ORDER BY batch_id DESC) AS rn
    FROM meta.etl_batch
    WHERE pipeline_name LIKE N'%yellow%' AND status = N'Success' AND ISNULL(rows_read, 0) > 0
)
SELECT e.period_key, e.total_rows AS expected_rows, b.rows_read, b.rows_loaded, b.rows_rejected,
       CASE WHEN b.rows_read = e.total_rows THEN N'PASS' ELSE N'FAIL' END AS read_equals_file,
       CASE WHEN b.rows_loaded + b.rows_rejected = b.rows_read THEN N'PASS' ELSE N'FAIL' END AS balanced,
       CASE WHEN b.rows_rejected >= e.min_rejects THEN N'PASS' ELSE N'CHECK' END AS rejects_ge_min,
       CAST(100.0 * b.rows_rejected / NULLIF(b.rows_read, 0) AS DECIMAL(6,2)) AS reject_pct
FROM exp e
LEFT JOIN b ON b.period_key = e.period_key AND b.rn = 1;

-- ===== C. So dong that trong bang (phai khop log) =====
SELECT (SELECT COUNT_BIG(*) FROM stg.yellow_trip)        AS stg_rows,
       (SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject) AS reject_rows;

-- ===== D. Khong con dong vi pham quy tac trong stg.yellow_trip (tat ca phai = 0) =====
SELECT
    SUM(CASE WHEN dropoff_datetime <= pickup_datetime THEN 1 ELSE 0 END)                       AS dropoff_le_pickup,
    SUM(CASE WHEN DATEDIFF(SECOND, pickup_datetime, dropoff_datetime) > 86400 THEN 1 ELSE 0 END) AS over_24h,
    SUM(CASE WHEN fare_amount < 0 THEN 1 ELSE 0 END)                                           AS fare_negative,
    SUM(CASE WHEN total_amount < 0 THEN 1 ELSE 0 END)                                          AS total_negative,
    SUM(CASE WHEN total_amount > 1000 THEN 1 ELSE 0 END)                                       AS total_gt_1000,
    SUM(CASE WHEN trip_distance IS NULL OR trip_distance <= 0 THEN 1 ELSE 0 END)               AS distance_bad,
    SUM(CASE WHEN pickup_datetime IS NULL OR dropoff_datetime IS NULL THEN 1 ELSE 0 END)       AS null_datetime
FROM stg.yellow_trip;

-- ===== E. Dong khong duoc loai nham: nhom null passenger_count (Flex Fare) phai con giu lai =====
-- 2024-01 co 140,162 dong null (2025-01: 540,149) trong tep goc; sau khi loai dong loi khac,
-- so con lai phai gan voi so nay, khong bang 0.
SELECT COUNT_BIG(*) AS null_passenger_rows
FROM stg.yellow_trip
WHERE passenger_count IS NULL;

-- ===== F. Thang cua du lieu (giu dung ky nap) =====
 
-- ===== G. Ly do bi loai =====
SELECT reject_reason, COUNT_BIG(*) AS n
FROM stg.yellow_trip_reject
GROUP BY reject_reason
ORDER BY n DESC;

-- ===== H. Chay lai co bi nap trung khong? =====
-- Moi thang chi nen co dong du lieu thuoc MOT batch thanh cong (batch loi phai co 0 dong).
SELECT b.period_key, b.batch_id, b.status, COUNT_BIG(s.batch_id) AS rows_in_stg
FROM meta.etl_batch b
LEFT JOIN stg.yellow_trip s ON s.batch_id = b.batch_id
WHERE b.pipeline_name LIKE N'%yellow%'
GROUP BY b.period_key, b.batch_id, b.status
ORDER BY b.period_key, b.batch_id;

-- ===== J. Bang trang thai nap theo thang =====
SELECT * FROM meta.etl_load_control ORDER BY dataset, period_key;
GO
