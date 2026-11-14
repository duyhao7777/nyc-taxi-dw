-- 02_stg_taxi_zone.sql
-- Bang Staging cho danh muc Taxi Zones (265 dong). Nguon: taxi_zone_lookup.csv

USE NYCTaxi_DW;
GO

IF OBJECT_ID(N'stg.taxi_zone') IS NULL
CREATE TABLE stg.taxi_zone (
    location_id   INT           NOT NULL PRIMARY KEY,
    borough       NVARCHAR(50)  NULL,     -- Queens, Manhattan, ..., EWR, Unknown, N/A
    zone          NVARCHAR(100) NULL,
    service_zone  NVARCHAR(50)  NULL,
    batch_id      INT           NULL,     -- tham chieu meta.etl_batch
    loaded_at     DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);
GO
