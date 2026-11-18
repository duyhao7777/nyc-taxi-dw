-- 03_dds_tables.sql
-- Tang DDS cua NYCTaxi_DW: 8 Dimension + 1 Fact theo thiet ke Giai doan 1 (bao cao GĐ1, muc II.5).
-- Grain: 1 dong dds.fact_trip = 1 chuyen taxi vang hop le (= 1 dong stg.yellow_trip).
-- Mapping: docs/mapping.xlsx. Phu trach: Cuong. Chay trong ADS/SSMS tren database NYCTaxi_DW.
-- File nay IDEMPOTENT: chay lai nhieu lan khong lam hong du lieu.
-- CHU Y: tat ca chuoi literal trong file nay deu ASCII de khong loi encoding khi chay file tren may khac.
--
-- Danh sach bang (theo GĐ1):
--   1  dds.dim_date            (Type 0) - lich 2015-01-01 den 2026-12-31
--   2  dds.dim_time            (Type 0) - 1440 phut trong ngay, 4 khung gio (G4)
--   3  dds.dim_location        (Type 1) - 265 vung + dong Unknown
--   4  dds.dim_vendor          (Type 2 co dieu kien) - ma 1, 2, 6, 7 (G8)
--   5  dds.dim_payment_type    (Type 1) - ma 0 den 6
--   6  dds.dim_rate_code       (Type 1) - ma 1 den 6, 99 = Unknown
--   7  dds.dim_passenger_group (Type 0) - 1 / 2-4 / 5-6 / Unknown (G5)
--   8  dds.dim_distance_band   (Type 0) - <1, 1-3, 3-7, 7-15, >=15, Invalid (G3)
--   9  dds.fact_trip           - 1 dong = 1 chuyen, 11 khoa ngoai, day du measure cua GĐ1

USE NYCTaxi_DW;
GO

-- ============================================================================
-- 1. DIM DATE (khoa thay the yyyymmdd; Type 0)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_date') IS NULL
BEGIN
    CREATE TABLE dds.dim_date (
        date_key      INT      NOT NULL PRIMARY KEY,  -- yyyymmdd
        full_date     DATE     NOT NULL UNIQUE,       -- GĐ1: full_date là Unique
        year_num      SMALLINT NOT NULL,
        quarter_num   TINYINT  NOT NULL,
        month_num     TINYINT  NOT NULL,
        day_num       TINYINT  NOT NULL,
        week_num      TINYINT  NOT NULL,             -- ISO week (GĐ1: week)
        day_of_week   TINYINT  NOT NULL,             -- 1=Mon..7=Sun (DATEFIRST 1)
        is_weekend    BIT      NOT NULL
    );
END;
GO

-- Nang cap ban cu: gan UNIQUE cho full_date (GĐ1: full_date là Unique)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns c ON c.object_id = i.object_id AND c.index_id = i.index_id
    JOIN sys.columns col ON col.object_id = c.object_id AND col.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(N'dds.dim_date')
      AND i.is_unique = 1 AND i.is_primary_key = 0
      AND col.name = 'full_date')
    CREATE UNIQUE INDEX UX_dim_date_full_date ON dds.dim_date(full_date);
GO

-- Nang cap ban cu (thieu week_num)
IF COL_LENGTH(N'dds.dim_date', N'week_num') IS NULL
    ALTER TABLE dds.dim_date ADD week_num TINYINT NULL;
GO

SET DATEFIRST 1;
GO

WITH d AS (
    SELECT CAST('2015-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM d WHERE d < '2026-12-31'
)
INSERT INTO dds.dim_date (date_key, full_date, year_num, quarter_num, month_num, day_num, week_num, day_of_week, is_weekend)
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d, YEAR(d), DATEPART(QUARTER, d), MONTH(d), DAY(d),
    DATEPART(ISO_WEEK, d),
    DATEPART(WEEKDAY, d),
    CASE WHEN DATEPART(WEEKDAY, d) >= 6 THEN 1 ELSE 0 END
FROM d
WHERE NOT EXISTS (SELECT 1 FROM dds.dim_date x WHERE x.full_date = d)
OPTION (MAXRECURSION 0);
GO

UPDATE dds.dim_date SET week_num = DATEPART(ISO_WEEK, full_date) WHERE week_num IS NULL;
GO

-- ============================================================================
-- 2. DIM TIME (1440 dong: 00:00 - 23:59; 4 khung gio theo G4)
--    time_key = hour*60 + minute + 1  (1..1440) => khoa on dinh, khong doi khi nap lai
-- ============================================================================
IF OBJECT_ID(N'dds.dim_time') IS NULL
BEGIN
    CREATE TABLE dds.dim_time (
        time_key        SMALLINT     NOT NULL PRIMARY KEY,
        hour_num        TINYINT      NOT NULL,
        minute_num      TINYINT      NOT NULL,
        time_band       NVARCHAR(20) NOT NULL,   -- Night / Morning / Afternoon / Evening
        time_band_order TINYINT      NOT NULL    -- 1..4, thu tu hien thi
    );
END;
GO

WITH t AS (
    SELECT 0 AS m
    UNION ALL
    SELECT m + 1 FROM t WHERE m < 1439
)
INSERT INTO dds.dim_time (time_key, hour_num, minute_num, time_band, time_band_order)
SELECT
    m + 1,
    m / 60,
    m % 60,
    CASE WHEN m / 60 < 6 THEN 'Night' WHEN m / 60 < 12 THEN 'Morning'
         WHEN m / 60 < 18 THEN 'Afternoon' ELSE 'Evening' END,
    CASE WHEN m / 60 < 6 THEN 1 WHEN m / 60 < 12 THEN 2 WHEN m / 60 < 18 THEN 3 ELSE 4 END
FROM t
WHERE NOT EXISTS (SELECT 1 FROM dds.dim_time x WHERE x.time_key = m + 1)
OPTION (MAXRECURSION 0);
GO

-- ============================================================================
-- 3. DIM LOCATION (khoa thay the + khoa tu nhien 1-265; Type 1)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_location') IS NULL
BEGIN
    CREATE TABLE dds.dim_location (
        location_key    INT           IDENTITY(1,1) PRIMARY KEY,
        location_id     INT           NOT NULL UNIQUE,   -- khoa tu nhien tu stg.taxi_zone
        borough         NVARCHAR(50)  NULL,
        zone            NVARCHAR(100) NULL,
        service_zone    NVARCHAR(50)  NULL
    );
END;
GO

-- Dong Unknown de FK pu/do khong bao gio vi pham
IF NOT EXISTS (SELECT 1 FROM dds.dim_location WHERE location_id = -1)
    INSERT INTO dds.dim_location (location_id, borough, zone, service_zone)
    VALUES (-1, N'Unknown', N'Unknown', N'Unknown');
GO

-- ============================================================================
-- 4. DIM VENDOR (G8: ma 1 CMT, 2 VTS/Curb Mobility, 6 Myle, 7 Helix)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_vendor') IS NULL
BEGIN
    CREATE TABLE dds.dim_vendor (
        vendor_key  SMALLINT IDENTITY(1,1) PRIMARY KEY,
        vendor_code SMALLINT NOT NULL UNIQUE,   -- ma nha cung cap
        vendor_name NVARCHAR(50) NOT NULL,
        vendor_note NVARCHAR(200) NULL          -- ghi chu ten goi qua cac giai doan
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dds.dim_vendor WHERE vendor_code = -1)
    INSERT INTO dds.dim_vendor (vendor_code, vendor_name, vendor_note)
    VALUES (-1, 'Unknown', 'Vendor code not in lookup (G8: 1, 2, 6, 7)');
IF NOT EXISTS (SELECT 1 FROM dds.dim_vendor WHERE vendor_code = 1)
    INSERT INTO dds.dim_vendor (vendor_code, vendor_name, vendor_note)
    VALUES (1, 'CMT', 'Creative Mobile Technologies');
IF NOT EXISTS (SELECT 1 FROM dds.dim_vendor WHERE vendor_code = 2)
    INSERT INTO dds.dim_vendor (vendor_code, vendor_name, vendor_note)
    VALUES (2, 'VTS (Curb Mobility)', 'VeriFone Taxicab Solutions, renamed Curb Mobility in 03/2025');
IF NOT EXISTS (SELECT 1 FROM dds.dim_vendor WHERE vendor_code = 6)
    INSERT INTO dds.dim_vendor (vendor_code, vendor_name, vendor_note)
    VALUES (6, 'Myle', 'Very small volume');
IF NOT EXISTS (SELECT 1 FROM dds.dim_vendor WHERE vendor_code = 7)
    INSERT INTO dds.dim_vendor (vendor_code, vendor_name, vendor_note)
    VALUES (7, 'Helix', 'Very small volume');
GO

-- ============================================================================
-- 5. DIM PAYMENT TYPE (GĐ1: 0 Flex Fare, 1 Credit card, 2 Cash, 3 No charge,
--    4 Dispute, 5 Unknown, 6 Voided trip)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_payment_type') IS NULL
BEGIN
    CREATE TABLE dds.dim_payment_type (
        payment_key        SMALLINT IDENTITY(1,1) PRIMARY KEY,
        payment_code       SMALLINT NOT NULL UNIQUE,   -- ma hinh thuc thanh toan
        payment_name       NVARCHAR(50) NOT NULL,
        payment_description NVARCHAR(200) NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = -1)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (-1, 'Unknown', 'Payment type not in lookup or NULL');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 0)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (0, 'Flex Fare', 'Metered fare, payment collected outside the vehicle');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 1)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (1, 'Credit card', 'Credit card payment');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 2)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (2, 'Cash', 'Cash payment');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 3)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (3, 'No charge', 'No charge trip');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 4)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (4, 'Dispute', 'Disputed payment');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 5)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (5, 'Unknown', 'Unknown payment type (data dictionary)');
IF NOT EXISTS (SELECT 1 FROM dds.dim_payment_type WHERE payment_code = 6)
    INSERT INTO dds.dim_payment_type (payment_code, payment_name, payment_description)
    VALUES (6, 'Voided trip', 'Voided trip');
GO

-- ============================================================================
-- 6. DIM RATE CODE (1 Standard, 2 JFK, 3 Newark, 4 Nassau/Westchester,
--    5 Negotiated fare, 6 Group ride, 99 = Unknown)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_rate_code') IS NULL
BEGIN
    CREATE TABLE dds.dim_rate_code (
        rate_code_key        SMALLINT IDENTITY(1,1) PRIMARY KEY,
        rate_code_id         SMALLINT NOT NULL UNIQUE,   -- ma bieu phi tu TLC
        rate_code_name       NVARCHAR(50) NOT NULL,
        rate_code_description NVARCHAR(200) NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = -1)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (-1, 'Unknown', 'Rate code not in lookup or NULL');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 1)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (1, 'Standard rate', 'Standard metered fare');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 2)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (2, 'JFK', 'JFK flat fare');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 3)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (3, 'Newark', 'Newark flat fare');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 4)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (4, 'Nassau or Westchester', 'Negotiated fare outside NYC');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 5)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (5, 'Negotiated fare', 'Negotiated fare');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 6)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (6, 'Group ride', 'Group ride');
IF NOT EXISTS (SELECT 1 FROM dds.dim_rate_code WHERE rate_code_id = 99)
    INSERT INTO dds.dim_rate_code (rate_code_id, rate_code_name, rate_code_description)
    VALUES (99, 'Unknown', 'Rate code 99 or empty value');
GO

-- ============================================================================
-- 7. DIM PASSENGER GROUP (G5: 1 người, 2-4 người, 5-6 người, Unknown)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_passenger_group') IS NULL
BEGIN
    CREATE TABLE dds.dim_passenger_group (
        passenger_group_key SMALLINT IDENTITY(1,1) PRIMARY KEY,
        group_name          NVARCHAR(30) NOT NULL UNIQUE,
        min_passengers      TINYINT NULL,
        max_passengers      TINYINT NULL,
        group_order         TINYINT NOT NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dds.dim_passenger_group WHERE group_name = 'Single_passenger')
    INSERT INTO dds.dim_passenger_group (group_name, min_passengers, max_passengers, group_order)
    VALUES ('Single_passenger', 1, 1, 1);
IF NOT EXISTS (SELECT 1 FROM dds.dim_passenger_group WHERE group_name = 'Small_group')
    INSERT INTO dds.dim_passenger_group (group_name, min_passengers, max_passengers, group_order)
    VALUES ('Small_group', 2, 4, 2);
IF NOT EXISTS (SELECT 1 FROM dds.dim_passenger_group WHERE group_name = 'Large_group')
    INSERT INTO dds.dim_passenger_group (group_name, min_passengers, max_passengers, group_order)
    VALUES ('Large_group', 5, 6, 3);
IF NOT EXISTS (SELECT 1 FROM dds.dim_passenger_group WHERE group_name = 'Unknown')
    INSERT INTO dds.dim_passenger_group (group_name, min_passengers, max_passengers, group_order)
    VALUES ('Unknown', NULL, NULL, 4);
GO

-- ============================================================================
-- 8. DIM DISTANCE BAND (G3: <1, 1-3, 3-7, 7-15, >=15 (den 100), Invalid)
-- ============================================================================
IF OBJECT_ID(N'dds.dim_distance_band') IS NULL
BEGIN
    CREATE TABLE dds.dim_distance_band (
        distance_band_key SMALLINT IDENTITY(1,1) PRIMARY KEY,
        band_name         NVARCHAR(30) NOT NULL UNIQUE,
        min_distance      DECIMAL(6,2) NULL,   -- dam
        max_distance      DECIMAL(6,2) NULL,
        band_order        TINYINT NOT NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dds.dim_distance_band WHERE band_name = 'Under 1 mile')
    INSERT INTO dds.dim_distance_band (band_name, min_distance, max_distance, band_order)
    VALUES ('Under 1 mile', 0, 1, 1);
IF NOT EXISTS (SELECT 1 FROM dds.dim_distance_band WHERE band_name = '1 to 3 miles')
    INSERT INTO dds.dim_distance_band (band_name, min_distance, max_distance, band_order)
    VALUES ('1 to 3 miles', 1, 3, 2);
IF NOT EXISTS (SELECT 1 FROM dds.dim_distance_band WHERE band_name = '3 to 7 miles')
    INSERT INTO dds.dim_distance_band (band_name, min_distance, max_distance, band_order)
    VALUES ('3 to 7 miles', 3, 7, 3);
IF NOT EXISTS (SELECT 1 FROM dds.dim_distance_band WHERE band_name = '7 to 15 miles')
    INSERT INTO dds.dim_distance_band (band_name, min_distance, max_distance, band_order)
    VALUES ('7 to 15 miles', 7, 15, 4);
IF NOT EXISTS (SELECT 1 FROM dds.dim_distance_band WHERE band_name = '15 miles and up')
    INSERT INTO dds.dim_distance_band (band_name, min_distance, max_distance, band_order)
    VALUES ('15 miles and up', 15, 100, 5);
IF NOT EXISTS (SELECT 1 FROM dds.dim_distance_band WHERE band_name = 'Invalid')
    INSERT INTO dds.dim_distance_band (band_name, min_distance, max_distance, band_order)
    VALUES ('Invalid', NULL, NULL, 6);
GO

-- ============================================================================
-- 9. FACT TRIP (grain 1 dong = 1 dong stg.yellow_trip hop le)
--    11 khoa ngoai (Pickup/Dropoff cho Date, Time, Location + 5 chieu con lai)
--    va day du measure cua GĐ1 (trip_count, trip_duration, ...)
-- ============================================================================
IF OBJECT_ID(N'dds.fact_trip') IS NULL
BEGIN
    CREATE TABLE dds.fact_trip (
        fact_id               BIGINT        IDENTITY(1,1) PRIMARY KEY,  -- trip_key cua GĐ1
        stg_trip_id           BIGINT        NOT NULL,   -- truy vet staging
        pickup_datetime       DATETIME2(0)  NULL,
        dropoff_datetime      DATETIME2(0)  NULL,
        date_key              INT           NULL REFERENCES dds.dim_date(date_key),          -- pickup_date_key
        dropoff_date_key      INT           NULL REFERENCES dds.dim_date(date_key),          -- dropoff_date_key
        pu_location_key       INT           NOT NULL REFERENCES dds.dim_location(location_key),  -- pickup_location_key
        do_location_key       INT           NOT NULL REFERENCES dds.dim_location(location_key),  -- dropoff_location_key
        pickup_time_key       SMALLINT      NULL REFERENCES dds.dim_time(time_key),
        dropoff_time_key      SMALLINT      NULL REFERENCES dds.dim_time(time_key),
        vendor_key            SMALLINT      NULL REFERENCES dds.dim_vendor(vendor_key),
        payment_key           SMALLINT      NULL REFERENCES dds.dim_payment_type(payment_key),
        rate_code_key         SMALLINT      NULL REFERENCES dds.dim_rate_code(rate_code_key),
        passenger_group_key   SMALLINT      NULL REFERENCES dds.dim_passenger_group(passenger_group_key),
        distance_band_key     SMALLINT      NULL REFERENCES dds.dim_distance_band(distance_band_key),
        trip_count            TINYINT       NOT NULL DEFAULT 1,   -- = 1 o moi dong (GĐ1)
        trip_duration         SMALLINT      NULL,       -- phut = dropoff - pickup
        vendor_id             SMALLINT      NULL,       -- ma goc (de doi soat)
        rate_code_id          SMALLINT      NULL,
        payment_type          SMALLINT      NULL,
        passenger_count       TINYINT       NULL,
        trip_distance         DECIMAL(10,2) NULL,
        fare_amount           DECIMAL(10,2) NULL,
        extra                 DECIMAL(10,2) NULL,
        mta_tax               DECIMAL(10,2) NULL,
        tip_amount            DECIMAL(10,2) NULL,
        tolls_amount          DECIMAL(10,2) NULL,
        improvement_surcharge DECIMAL(10,2) NULL,
        total_amount          DECIMAL(10,2) NULL,
        congestion_surcharge  DECIMAL(10,2) NULL,
        airport_fee           DECIMAL(10,2) NULL,
        cbd_congestion_fee    DECIMAL(10,2) NULL,
        batch_id              INT           NULL,       -- tham chieu meta.etl_batch
        period_key            CHAR(7)       NULL        -- thang du lieu yyyy-MM
    );

    CREATE NONCLUSTERED INDEX IX_fact_trip_batch  ON dds.fact_trip(batch_id);
    CREATE NONCLUSTERED INDEX IX_fact_trip_period ON dds.fact_trip(period_key);
    CREATE NONCLUSTERED INDEX IX_fact_trip_date   ON dds.fact_trip(date_key);
    CREATE NONCLUSTERED INDEX IX_fact_trip_pu_do  ON dds.fact_trip(pu_location_key, do_location_key);
END;
GO

-- Nang cap ban cu (bang da co du lieu, thieu cot moi)
IF COL_LENGTH(N'dds.fact_trip', N'dropoff_date_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD dropoff_date_key INT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_dropoff_date FOREIGN KEY (dropoff_date_key) REFERENCES dds.dim_date(date_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'pickup_time_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD pickup_time_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_pickup_time FOREIGN KEY (pickup_time_key) REFERENCES dds.dim_time(time_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'dropoff_time_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD dropoff_time_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_dropoff_time FOREIGN KEY (dropoff_time_key) REFERENCES dds.dim_time(time_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'vendor_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD vendor_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_vendor FOREIGN KEY (vendor_key) REFERENCES dds.dim_vendor(vendor_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'payment_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD payment_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_payment FOREIGN KEY (payment_key) REFERENCES dds.dim_payment_type(payment_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'rate_code_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD rate_code_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_rate_code FOREIGN KEY (rate_code_key) REFERENCES dds.dim_rate_code(rate_code_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'passenger_group_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD passenger_group_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_passenger_group FOREIGN KEY (passenger_group_key) REFERENCES dds.dim_passenger_group(passenger_group_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'distance_band_key') IS NULL
BEGIN
    ALTER TABLE dds.fact_trip ADD distance_band_key SMALLINT NULL;
    ALTER TABLE dds.fact_trip ADD CONSTRAINT FK_fact_trip_distance_band FOREIGN KEY (distance_band_key) REFERENCES dds.dim_distance_band(distance_band_key);
END;
GO
IF COL_LENGTH(N'dds.fact_trip', N'trip_count') IS NULL
    ALTER TABLE dds.fact_trip ADD trip_count TINYINT NOT NULL DEFAULT 1;
GO
IF COL_LENGTH(N'dds.fact_trip', N'trip_duration') IS NULL
    ALTER TABLE dds.fact_trip ADD trip_duration SMALLINT NULL;
GO

-- Backfill cho bang da co du lieu (chay 1 lan; voi bang rong thi khong ton tai dong nao)
UPDATE dds.fact_trip
SET trip_count = 1
WHERE trip_count IS NULL OR trip_count <> 1;
GO
UPDATE dds.fact_trip
SET trip_duration = DATEDIFF(MINUTE, pickup_datetime, dropoff_datetime)
WHERE trip_duration IS NULL AND pickup_datetime IS NOT NULL AND dropoff_datetime IS NOT NULL;
GO

-- ============================================================================
-- 10. Kiem tra ket qua
-- ============================================================================
SELECT t.name AS bang, p.rows AS so_dong
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE SCHEMA_NAME(t.schema_id) = 'dds'
ORDER BY t.name;
GO
SELECT
    (SELECT COUNT(*) FROM dds.dim_date)            AS dim_date,
    (SELECT COUNT(*) FROM dds.dim_time)            AS dim_time,
    (SELECT COUNT(*) FROM dds.dim_location)        AS dim_location,
    (SELECT COUNT(*) FROM dds.dim_vendor)          AS dim_vendor,
    (SELECT COUNT(*) FROM dds.dim_payment_type)    AS dim_payment_type,
    (SELECT COUNT(*) FROM dds.dim_rate_code)       AS dim_rate_code,
    (SELECT COUNT(*) FROM dds.dim_passenger_group) AS dim_passenger_group,
    (SELECT COUNT(*) FROM dds.dim_distance_band)   AS dim_distance_band,
    (SELECT COUNT(*) FROM dds.fact_trip)           AS fact_trip;
GO
