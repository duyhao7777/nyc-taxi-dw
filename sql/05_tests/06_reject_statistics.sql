-- 06_reject_statistics.sql
-- Thong ke so lieu lam sach va bang Reject (Phuc vu bao cao cua Hieu)
-- Ket qua can co: Bang reject, so lieu

USE NYCTaxi_DW;
GO
SET NOCOUNT ON;

PRINT '======================================================';
PRINT 'BAO CAO THONG KE LAM SACH DU LIEU VA BANG REJECT';
PRINT 'Nguoi thuc hien: Hieu';
PRINT '======================================================';

-- 1. TONG QUAN SO LIEU NAP VA REJECT
SELECT 
    '1. Tong quan' AS [Muc],
    (SELECT COUNT_BIG(*) FROM stg.yellow_trip) AS [So dong hop le (stg.yellow_trip)],
    (SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject) AS [So dong reject (stg.yellow_trip_reject)],
    (SELECT COUNT_BIG(*) FROM stg.yellow_trip) + (SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject) AS [Tong so dong nguon],
    CAST(
        ROUND(
            (SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject) * 100.0 / 
            NULLIF((SELECT COUNT_BIG(*) FROM stg.yellow_trip) + (SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject), 0),
            2
        ) AS DECIMAL(5,2)
    ) AS [Ty le Reject (%)];

-- 2. SO LIEU CHI TIET THEO TUNG TEP / KY NAP
SELECT 
    source_file AS [Tep nguon],
    COUNT_BIG(CASE WHEN tbl = 'valid' THEN 1 END) AS [Hop le],
    COUNT_BIG(CASE WHEN tbl = 'reject' THEN 1 END) AS [Reject],
    COUNT_BIG(*) AS [Tong so dong],
    CAST(
        ROUND(
            COUNT_BIG(CASE WHEN tbl = 'reject' THEN 1 END) * 100.0 / NULLIF(COUNT_BIG(*), 0),
            2
        ) AS DECIMAL(5,2)
    ) AS [Ty le Reject (%)]
FROM (
    SELECT source_file, 'valid' AS tbl FROM stg.yellow_trip
    UNION ALL
    SELECT source_file, 'reject' AS tbl FROM stg.yellow_trip_reject
) AS combined
GROUP BY source_file
ORDER BY source_file;

-- 3. PHAN RA CHI TIET THEO LY DO REJECT (MUC I.4)
SELECT 
    reject_reason AS [Ly do vi pham (reject_reason)],
    COUNT_BIG(*) AS [So ban ghi],
    CAST(
        ROUND(
            COUNT_BIG(*) * 100.0 / NULLIF((SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject), 0),
            2
        ) AS DECIMAL(5,2)
    ) AS [Ty le trong tong Reject (%)]
FROM stg.yellow_trip_reject
GROUP BY reject_reason
ORDER BY [So ban ghi] DESC;

-- 4. THONG KE SO DONG VI PHAM THEO TUNG NHOM QUY TAC DON
SELECT 
    [Quy tac vi pham],
    COUNT_BIG(*) AS [So ban ghi vi pham]
FROM (
    SELECT 'Quang duong <= 0 (DISTANCE_LE_ZERO)' AS [Quy tac vi pham] FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%DISTANCE_LE_ZERO%'
    UNION ALL
    SELECT 'Gio tra truoc/bang gio don (DROPOFF_LE_PICKUP)' FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%DROPOFF_LE_PICKUP%'
    UNION ALL
    SELECT 'Tien cuoc am (NEGATIVE_FARE)' FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%NEGATIVE_FARE%'
    UNION ALL
    SELECT 'Tong tien khong hop le (<0 hoac >1000) (INVALID_TOTAL_AMOUNT)' FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%INVALID_TOTAL_AMOUNT%'
    UNION ALL
    SELECT 'Thoi gian ngoai ky nap (OUT_OF_PERIOD)' FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%OUT_OF_PERIOD%'
    UNION ALL
    SELECT 'Thoi luong vuot qua 24 gio (DURATION_EXCEEDS_24H)' FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%DURATION_EXCEEDS_24H%'
    UNION ALL
    SELECT 'Thoi gian NULL / loi parse (INVALID_DATETIME)' FROM stg.yellow_trip_reject WHERE reject_reason LIKE '%INVALID_DATETIME%'
) AS rules
GROUP BY [Quy tac vi pham]
ORDER BY [So ban ghi vi pham] DESC;

-- 5. XEM MAU 10 DONG BI REJECT
SELECT TOP 10
    reject_id,
    reject_reason,
    pickup_datetime,
    dropoff_datetime,
    trip_distance,
    fare_amount,
    total_amount,
    source_file,
    source_row_number
FROM stg.yellow_trip_reject
ORDER BY reject_id;
GO
