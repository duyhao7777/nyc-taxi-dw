-- 03_dds_tables.sql
-- Tang DDS: dim_location, dim_date, fact_trip. Grain fact 1:1 voi stg.yellow_trip
-- (giu check 5+6 file 05_reconcile_checks.sql PASS). Mapping: docs/mapping.xlsx.
-- Phu trach: Cuong. Chay trong TablePro/ADS tren database NYCTaxi_DW.

USE NYCTaxi_DW;
GO

-- 1. DIM LOCATION (khoa thay the + khoa tu nhien 1-265)
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

-- 2. DIM DATE (sinh san 2015-2026, nap 1 lan)
IF OBJECT_ID(N'dds.dim_date') IS NULL
BEGIN
    CREATE TABLE dds.dim_date (
        date_key      INT    NOT NULL PRIMARY KEY,  -- yyyymmdd
        full_date     DATE   NOT NULL,
        year_num      SMALLINT NOT NULL,
        quarter_num   TINYINT  NOT NULL,
        month_num     TINYINT  NOT NULL,
        day_num       TINYINT  NOT NULL,
        day_of_week   TINYINT  NOT NULL,            -- 1=Mon..7=Sun (DATEFIRST 1)
        is_weekend    BIT      NOT NULL
    );
END;
GO

SET DATEFIRST 1;
;WITH d AS (
    SELECT CAST('2015-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM d WHERE d < '2026-12-31'
)
INSERT INTO dds.dim_date (date_key, full_date, year_num, quarter_num, month_num, day_num, day_of_week, is_weekend)
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d, YEAR(d), DATEPART(QUARTER, d), MONTH(d), DAY(d),
    DATEPART(WEEKDAY, d),
    CASE WHEN DATEPART(WEEKDAY, d) >= 6 THEN 1 ELSE 0 END
FROM d
WHERE NOT EXISTS (SELECT 1 FROM dds.dim_date x WHERE x.full_date = d)
OPTION (MAXRECURSION 0);
GO

-- 3. FACT TRIP (grain 1 dong = 1 dong stg.yellow_trip)
IF OBJECT_ID(N'dds.fact_trip') IS NULL
BEGIN
    CREATE TABLE dds.fact_trip (
        fact_id               BIGINT        IDENTITY(1,1) PRIMARY KEY,
        stg_trip_id           BIGINT        NOT NULL,   -- truy vet staging
        pickup_datetime       DATETIME2(0)  NULL,
        dropoff_datetime      DATETIME2(0)  NULL,
        date_key              INT           NULL REFERENCES dds.dim_date(date_key),
        pu_location_key       INT           NOT NULL REFERENCES dds.dim_location(location_key),
        do_location_key       INT           NOT NULL REFERENCES dds.dim_location(location_key),
        vendor_id             SMALLINT      NULL,
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

SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID(N'dds') ORDER BY name;
GO
SELECT (SELECT COUNT(*) FROM dds.dim_location) AS dim_location,
       (SELECT COUNT(*) FROM dds.dim_date) AS dim_date,
       (SELECT COUNT(*) FROM dds.fact_trip) AS fact_trip;
GO
