-- 02_stg_yellow_trip.sql
-- Bang Staging cho du lieu Yellow Taxi Trip va bang luu cac ban ghi bi Reject.
-- Nguon: Parquet files (yellow_tripdata_YYYY-MM.parquet)
-- Phụ trách: Hieu

USE NYCTaxi_DW;
GO

-- 1. BANG STAGING YELLOW TRIP (Cac ban ghi da chuan hoa va vuot qua kiem tra G9)
IF OBJECT_ID(N'stg.yellow_trip') IS NULL
BEGIN
    CREATE TABLE stg.yellow_trip (
        stg_trip_id             BIGINT IDENTITY(1,1) PRIMARY KEY,
        
        -- Thong tin chuyen di
        vendor_id               SMALLINT        NULL,
        pickup_datetime         DATETIME2(0)    NULL,
        dropoff_datetime        DATETIME2(0)    NULL,
        passenger_count         TINYINT         NULL,
        trip_distance           DECIMAL(10,2)   NULL,
        rate_code_id            SMALLINT        NULL,
        store_and_fwd_flag      CHAR(1)         NULL,
        pu_location_id          INT             NULL,
        do_location_id          INT             NULL,
        payment_type            SMALLINT        NULL,
        
        -- Cac khoan tien va phu phi (chuan hoa cho moi nam)
        fare_amount             DECIMAL(10,2)   NULL,
        extra                   DECIMAL(10,2)   NULL,
        mta_tax                 DECIMAL(10,2)   NULL,
        tip_amount              DECIMAL(10,2)   NULL,
        tolls_amount            DECIMAL(10,2)   NULL,
        improvement_surcharge   DECIMAL(10,2)   NULL,
        total_amount            DECIMAL(10,2)   NULL,
        congestion_surcharge    DECIMAL(10,2)   NULL DEFAULT 0,
        airport_fee             DECIMAL(10,2)   NULL DEFAULT 0,
        cbd_congestion_fee      DECIMAL(10,2)   NULL DEFAULT 0,
        
        -- Metadata truy vet va doi soat ETL
        batch_id                INT             NULL,     -- tham chieu meta.etl_batch
        source_file             VARCHAR(255)    NULL,
        source_row_number       BIGINT          NULL,
        loaded_at               DATETIME2       NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE NONCLUSTERED INDEX IX_stg_yellow_trip_batch_id ON stg.yellow_trip(batch_id);
    CREATE NONCLUSTERED INDEX IX_stg_yellow_trip_pickup ON stg.yellow_trip(pickup_datetime);
END;
GO

-- 2. BANG REJECT (Cac ban ghi vi pham G9: thoi gian sai, tien am, tong tien > 1000, ...)
IF OBJECT_ID(N'stg.yellow_trip_reject') IS NULL
BEGIN
    CREATE TABLE stg.yellow_trip_reject (
        reject_id               BIGINT IDENTITY(1,1) PRIMARY KEY,
        
        -- Du lieu chuyen vi pham
        vendor_id               SMALLINT        NULL,
        pickup_datetime         DATETIME2(0)    NULL,
        dropoff_datetime        DATETIME2(0)    NULL,
        passenger_count         TINYINT         NULL,
        trip_distance           DECIMAL(10,2)   NULL,
        rate_code_id            SMALLINT        NULL,
        store_and_fwd_flag      CHAR(1)         NULL,
        pu_location_id          INT             NULL,
        do_location_id          INT             NULL,
        payment_type            SMALLINT        NULL,
        fare_amount             DECIMAL(10,2)   NULL,
        extra                   DECIMAL(10,2)   NULL,
        mta_tax                 DECIMAL(10,2)   NULL,
        tip_amount              DECIMAL(10,2)   NULL,
        tolls_amount            DECIMAL(10,2)   NULL,
        improvement_surcharge   DECIMAL(10,2)   NULL,
        total_amount            DECIMAL(10,2)   NULL,
        congestion_surcharge    DECIMAL(10,2)   NULL,
        airport_fee             DECIMAL(10,2)   NULL,
        cbd_congestion_fee      DECIMAL(10,2)   NULL,
        
        -- Thong tin ly do reject va metadata
        reject_reason           VARCHAR(255)    NOT NULL, -- Vi du: INVALID_DATETIME, DURATION_OVER_24H, NEGATIVE_FARE, TOTAL_OVER_1000
        batch_id                INT             NULL,     -- tham chieu meta.etl_batch
        source_file             VARCHAR(255)    NULL,
        source_row_number       BIGINT          NULL,
        rejected_at             DATETIME2       NOT NULL DEFAULT SYSDATETIME()
    );

    CREATE NONCLUSTERED INDEX IX_stg_yellow_trip_reject_batch_id ON stg.yellow_trip_reject(batch_id);
END;
GO

SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID(N'stg') ORDER BY name;
GO
