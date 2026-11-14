-- 04_metadata_tables.sql
-- Cac bang Metadata: ghi lai moi lan chay ETL, loi, trang thai nap theo thang, va tu dien du lieu.

USE NYCTaxi_DW;
GO

-- 1. Moi lan chay mot buoc ETL = mot dong
IF OBJECT_ID(N'meta.etl_batch') IS NULL
CREATE TABLE meta.etl_batch (
    batch_id       INT IDENTITY(1,1) PRIMARY KEY,
    pipeline_name  NVARCHAR(100) NOT NULL,          -- ten pipeline, vi du load_taxi_zones
    layer          NVARCHAR(20)  NOT NULL,          -- Staging / DDS
    target_table   NVARCHAR(128) NULL,              -- bang dich, vi du stg.taxi_zone
    period_key     CHAR(7)       NULL,              -- thang du lieu, dang yyyy-MM
    start_time     DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    end_time       DATETIME2     NULL,
    status         NVARCHAR(20)  NOT NULL DEFAULT N'Running',   -- Running / Success / Failed
    rows_read      BIGINT        NULL,
    rows_loaded    BIGINT        NULL,
    rows_rejected  BIGINT        NULL,
    message        NVARCHAR(MAX) NULL
);
GO

-- 2. Chi tiet loi
IF OBJECT_ID(N'meta.etl_error_log') IS NULL
CREATE TABLE meta.etl_error_log (
    error_id       INT IDENTITY(1,1) PRIMARY KEY,
    batch_id       INT NULL REFERENCES meta.etl_batch(batch_id),
    step_name      NVARCHAR(100) NULL,
    error_time     DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    error_message  NVARCHAR(MAX) NULL
);
GO

-- 3. Thang nao da nap thanh cong (de khong nap lai, va de biet phai nap tiep tu dau)
IF OBJECT_ID(N'meta.etl_load_control') IS NULL
CREATE TABLE meta.etl_load_control (
    dataset        NVARCHAR(50) NOT NULL,           -- vi du yellow_trip
    period_key     CHAR(7)      NOT NULL,           -- yyyy-MM
    status         NVARCHAR(20) NOT NULL,           -- Success / Failed
    last_batch_id  INT NULL,
    loaded_at      DATETIME2    NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_etl_load_control PRIMARY KEY (dataset, period_key)
);
GO

-- 4. Tu dien du lieu (mo ta cot, nguon, quy tac bien doi) - dien tu file mapping
IF OBJECT_ID(N'meta.data_dictionary') IS NULL
CREATE TABLE meta.data_dictionary (
    layer           NVARCHAR(20)  NOT NULL,         -- Source / Staging / DDS
    table_name      NVARCHAR(128) NOT NULL,
    column_name     NVARCHAR(128) NOT NULL,
    data_type       NVARCHAR(50)  NULL,
    description     NVARCHAR(500) NULL,
    source_column   NVARCHAR(200) NULL,
    transform_rule  NVARCHAR(500) NULL,
    CONSTRAINT PK_data_dictionary PRIMARY KEY (layer, table_name, column_name)
);
GO

SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID(N'meta') ORDER BY name;
GO
