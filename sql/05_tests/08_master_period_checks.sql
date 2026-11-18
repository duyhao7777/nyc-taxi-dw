USE NYCTaxi_DW;
GO
SET NOCOUNT ON;
DECLARE @k CHAR(7)='2025-06'; -- CHANGE before running
DECLARE @sf VARCHAR(255)='yellow_tripdata_'+@k+'.parquet';
DECLARE @start DATE=CONVERT(DATE,@k+'-01'), @end DATE;
SET @end=DATEADD(MONTH,1,@start);
DECLARE @s BIGINT=(SELECT COUNT_BIG(*) FROM stg.yellow_trip WHERE source_file=@sf),
        @r BIGINT=(SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject WHERE source_file=@sf),
        @f BIGINT=(SELECT COUNT_BIG(*) FROM dds.fact_trip WHERE period_key=@k);
DECLARE @b INT=(SELECT last_batch_id FROM meta.etl_load_control WHERE dataset='yellow_trip' AND period_key=@k AND status='Success');
DECLARE @fb INT=(SELECT last_batch_id FROM meta.etl_load_control WHERE dataset='fact_trip' AND period_key=@k AND status='Success');
DECLARE @tests TABLE(id VARCHAR(10), test_name NVARCHAR(150), expected NVARCHAR(100), actual NVARCHAR(100), result VARCHAR(4));
INSERT @tests SELECT 'TC01',N'Zones 1..265',N'265',CONVERT(NVARCHAR(100),COUNT(*)),CASE WHEN COUNT(*)=265 AND MIN(location_id)=1 AND MAX(location_id)=265 THEN 'PASS' ELSE 'FAIL' END FROM stg.taxi_zone;
INSERT @tests SELECT 'TC02',N'Source log = valid + reject',CONVERT(NVARCHAR(100),@s+@r),COALESCE(CONVERT(NVARCHAR(100),(SELECT rows_read FROM meta.etl_batch WHERE batch_id=@b)),N'MISSING'),CASE WHEN EXISTS(SELECT 1 FROM meta.etl_batch WHERE batch_id=@b AND status='Success' AND rows_read=@s+@r AND rows_loaded=@s AND rows_rejected=@r) THEN 'PASS' ELSE 'FAIL' END;
INSERT @tests SELECT 'TC03',N'Fact count = staging',CONVERT(NVARCHAR(100),@s),CONVERT(NVARCHAR(100),@f),CASE WHEN @b IS NOT NULL AND @fb IS NOT NULL AND @s=@f THEN 'PASS' ELSE 'FAIL' END;
DECLARE @sr DECIMAL(38,2)=(SELECT COALESCE(SUM(total_amount),0) FROM stg.yellow_trip WHERE source_file=@sf),@fr DECIMAL(38,2)=(SELECT COALESCE(SUM(total_amount),0) FROM dds.fact_trip WHERE period_key=@k);
INSERT @tests SELECT 'TC04',N'Revenue reconciliation',CONVERT(NVARCHAR(100),@sr),CONVERT(NVARCHAR(100),@fr),CASE WHEN @b IS NOT NULL AND @fb IS NOT NULL AND @sr=@fr THEN 'PASS' ELSE 'FAIL' END;
INSERT @tests SELECT 'TC05',N'Duplicate fact stg_trip_id',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT stg_trip_id FROM dds.fact_trip WHERE period_key=@k GROUP BY stg_trip_id HAVING COUNT_BIG(*)>1) x;
INSERT @tests SELECT 'TC06',N'Broken lineage or foreign key',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM dds.fact_trip f LEFT JOIN stg.yellow_trip s ON s.stg_trip_id=f.stg_trip_id LEFT JOIN dds.dim_date d ON d.date_key=f.date_key LEFT JOIN dds.dim_location p ON p.location_key=f.pu_location_key LEFT JOIN dds.dim_location q ON q.location_key=f.do_location_key WHERE f.period_key=@k AND (s.stg_trip_id IS NULL OR s.source_file IS NULL OR s.source_file<>@sf OR d.date_key IS NULL OR p.location_key IS NULL OR q.location_key IS NULL);
INSERT @tests SELECT 'TC07',N'Invalid trips remaining (current code)',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM stg.yellow_trip WHERE source_file=@sf AND (pickup_datetime IS NULL OR dropoff_datetime IS NULL OR dropoff_datetime<=pickup_datetime OR DATEDIFF_BIG(SECOND,pickup_datetime,dropoff_datetime)>86400 OR pickup_datetime<@start OR pickup_datetime>=@end OR fare_amount<0 OR total_amount<0 OR total_amount>1000 OR trip_distance IS NULL OR trip_distance<=0);
INSERT @tests SELECT 'TC08',N'Missing reject reason',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM stg.yellow_trip_reject WHERE source_file=@sf AND (reject_reason IS NULL OR LTRIM(RTRIM(reject_reason))='');
INSERT @tests SELECT 'TC09',N'Latest batch controls',N'2 success',CONVERT(NVARCHAR(100),COUNT(*)),CASE WHEN COUNT(*)=2 THEN 'PASS' ELSE 'FAIL' END FROM meta.etl_load_control l JOIN meta.etl_batch b ON b.batch_id=l.last_batch_id WHERE l.period_key=@k AND l.dataset IN ('yellow_trip','fact_trip') AND l.status='Success' AND b.status='Success' AND b.period_key=@k;
INSERT @tests SELECT 'TC10',N'Duplicate source row across valid and reject',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT source_row_number FROM (SELECT source_row_number FROM stg.yellow_trip WHERE source_file=@sf UNION ALL SELECT source_row_number FROM stg.yellow_trip_reject WHERE source_file=@sf) q GROUP BY source_row_number HAVING COUNT_BIG(*)>1 OR source_row_number IS NULL) x;
INSERT @tests SELECT 'TC11',N'NULL total_amount in valid trips',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM stg.yellow_trip WHERE source_file=@sf AND total_amount IS NULL;
INSERT @tests SELECT 'TC12',N'Calendar coverage',CONVERT(NVARCHAR(100),DATEDIFF(DAY,@start,@end)),CONVERT(NVARCHAR(100),COUNT(*)),CASE WHEN COUNT(*)=DATEDIFF(DAY,@start,@end) THEN 'PASS' ELSE 'FAIL' END FROM dds.dim_date WHERE full_date>=@start AND full_date<@end;

-- GĐ1: 8 dimension + day du khoa ngoai + measure
DECLARE @dim_counts TABLE(tbl NVARCHAR(40), c INT, minc INT);
INSERT @dim_counts
SELECT 'dim_date', COUNT(*), 1 FROM dds.dim_date
UNION ALL SELECT 'dim_time', COUNT(*), 1440 FROM dds.dim_time
UNION ALL SELECT 'dim_location', COUNT(*), 266 FROM dds.dim_location
UNION ALL SELECT 'dim_vendor', COUNT(*), 5 FROM dds.dim_vendor
UNION ALL SELECT 'dim_payment_type', COUNT(*), 8 FROM dds.dim_payment_type
UNION ALL SELECT 'dim_rate_code', COUNT(*), 8 FROM dds.dim_rate_code
UNION ALL SELECT 'dim_passenger_group', COUNT(*), 4 FROM dds.dim_passenger_group
UNION ALL SELECT 'dim_distance_band', COUNT(*), 6 FROM dds.dim_distance_band;
INSERT @tests SELECT 'TC13',N'8 DDS dimensions populated (GĐ1)',N'8',CONVERT(NVARCHAR(100),(SELECT COUNT(*) FROM @dim_counts WHERE c>=minc)),CASE WHEN (SELECT COUNT(*) FROM @dim_counts WHERE c>=minc)=8 THEN 'PASS' ELSE 'FAIL' END;
INSERT @tests SELECT 'TC14',N'Fact rows with NULL or orphan dimension keys',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM dds.fact_trip f LEFT JOIN dds.dim_date dd ON dd.date_key=f.date_key LEFT JOIN dds.dim_time tp ON tp.time_key=f.pickup_time_key LEFT JOIN dds.dim_time tq ON tq.time_key=f.dropoff_time_key LEFT JOIN dds.dim_location pl ON pl.location_key=f.pu_location_key LEFT JOIN dds.dim_location dl ON dl.location_key=f.do_location_key LEFT JOIN dds.dim_vendor v ON v.vendor_key=f.vendor_key LEFT JOIN dds.dim_payment_type pay ON pay.payment_key=f.payment_key LEFT JOIN dds.dim_rate_code rc ON rc.rate_code_key=f.rate_code_key LEFT JOIN dds.dim_passenger_group pg ON pg.passenger_group_key=f.passenger_group_key LEFT JOIN dds.dim_distance_band db ON db.distance_band_key=f.distance_band_key WHERE f.period_key=@k AND (dd.date_key IS NULL OR tp.time_key IS NULL OR tq.time_key IS NULL OR pl.location_key IS NULL OR dl.location_key IS NULL OR v.vendor_key IS NULL OR pay.payment_key IS NULL OR rc.rate_code_key IS NULL OR pg.passenger_group_key IS NULL OR db.distance_band_key IS NULL OR f.trip_count<>1 OR f.trip_duration IS NULL);
INSERT @tests SELECT 'TC15',N'trip_count = 1 and trip_duration = dropoff - pickup',N'0',CONVERT(NVARCHAR(100),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM dds.fact_trip WHERE period_key=@k AND (trip_count<>1 OR trip_duration IS NULL OR trip_duration<>DATEDIFF(MINUTE,pickup_datetime,dropoff_datetime));
INSERT @tests SELECT 'TC16',N'Revenue joined through dimensions = total revenue',CONVERT(NVARCHAR(100),COALESCE((SELECT SUM(total_amount) FROM dds.fact_trip WHERE period_key=@k),0)),CONVERT(NVARCHAR(100),COALESCE((SELECT SUM(f.total_amount) FROM dds.fact_trip f JOIN dds.dim_vendor v ON v.vendor_key=f.vendor_key JOIN dds.dim_payment_type pay ON pay.payment_key=f.payment_key JOIN dds.dim_rate_code rc ON rc.rate_code_key=f.rate_code_key JOIN dds.dim_passenger_group pg ON pg.passenger_group_key=f.passenger_group_key JOIN dds.dim_distance_band db ON db.distance_band_key=f.distance_band_key WHERE f.period_key=@k),0)),CASE WHEN COALESCE((SELECT SUM(total_amount) FROM dds.fact_trip WHERE period_key=@k),0)=COALESCE((SELECT SUM(f.total_amount) FROM dds.fact_trip f JOIN dds.dim_vendor v ON v.vendor_key=f.vendor_key JOIN dds.dim_payment_type pay ON pay.payment_key=f.payment_key JOIN dds.dim_rate_code rc ON rc.rate_code_key=f.rate_code_key JOIN dds.dim_passenger_group pg ON pg.passenger_group_key=f.passenger_group_key JOIN dds.dim_distance_band db ON db.distance_band_key=f.distance_band_key WHERE f.period_key=@k),0) THEN 'PASS' ELSE 'FAIL' END;

SELECT @k AS period_key,* FROM @tests ORDER BY id;