-- 00_create_database.sql
-- Tao database NYCTaxi_DW voi 3 schema tuong ung 3 tang: stg (Staging), dds (DDS), meta (Metadata).
-- Tang Source la cac tep nguon (Parquet, CSV, Shapefile) nam trong thu muc data/source.
-- Chay trong SSMS (Execute).

IF DB_ID(N'NYCTaxi_DW') IS NULL
    CREATE DATABASE NYCTaxi_DW;
GO

USE NYCTaxi_DW;
GO

IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');
GO
IF SCHEMA_ID(N'dds') IS NULL EXEC(N'CREATE SCHEMA dds');
GO
IF SCHEMA_ID(N'meta') IS NULL EXEC(N'CREATE SCHEMA meta');
GO

SELECT name AS schema_name FROM sys.schemas WHERE name IN (N'stg', N'dds', N'meta');
GO
