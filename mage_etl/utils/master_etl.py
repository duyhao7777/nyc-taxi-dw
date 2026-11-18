"""Orchestration for one month. Existing component blocks remain authoritative."""
import os
from datetime import date
from pathlib import Path
from sqlalchemy import text
from mage_etl.utils.etl_common import get_engine, is_period_loaded
from mage_etl.data_loaders.load_zone_csv import load_zone_csv
from mage_etl.transformers.clean_zone import clean_zone
from mage_etl.data_exporters.export_stg_taxi_zone import export_stg_taxi_zone
from mage_etl.data_loaders.load_yellow_trip_to_staging import load_yellow_trip_to_staging
from mage_etl.data_exporters.sync_dim_location import sync_dim_location
from mage_etl.data_exporters.export_fact_trip import export_fact_trip


def month_bounds(period_key):
    if not isinstance(period_key, str) or len(period_key) != 7:
        raise ValueError('period_key must be YYYY-MM')
    start = date.fromisoformat(period_key + '-01')
    if start.strftime('%Y-%m') != period_key or not 2015 <= start.year <= 2026:
        raise ValueError('Supported scope: 2015-2026; verify each file schema')
    return start, date(start.year + (start.month == 12), start.month % 12 + 1, 1)


def reconcile(engine, period_key):
    start, end = month_bounds(period_key)
    params = {'k': period_key, 'd1': start, 'd2': end, 'sf': f'yellow_tripdata_{period_key}.parquet'}
    with engine.connect() as c:
        stg = c.execute(text('SELECT COUNT_BIG(*), COALESCE(SUM(total_amount),0), COUNT_BIG(total_amount) FROM stg.yellow_trip WHERE source_file=:sf'), params).one()
        fact = c.execute(text('SELECT COUNT_BIG(*), COALESCE(SUM(total_amount),0), COUNT_BIG(total_amount) FROM dds.fact_trip WHERE period_key=:k'), params).one()
        rejects = c.execute(text('SELECT COUNT_BIG(*) FROM stg.yellow_trip_reject WHERE source_file=:sf'), params).scalar()
        log = c.execute(text("""SELECT b.rows_read,b.rows_loaded,b.rows_rejected FROM meta.etl_load_control l JOIN meta.etl_batch b ON b.batch_id=l.last_batch_id WHERE l.dataset='yellow_trip' AND l.period_key=:k AND l.status='Success' AND b.status='Success'"""), params).one_or_none()
        dup = c.execute(text('SELECT COUNT_BIG(*) FROM (SELECT stg_trip_id FROM dds.fact_trip WHERE period_key=:k GROUP BY stg_trip_id HAVING COUNT_BIG(*)>1) d'), params).scalar()
        bad = c.execute(text('''SELECT COUNT_BIG(*) FROM dds.fact_trip f LEFT JOIN stg.yellow_trip s ON s.stg_trip_id=f.stg_trip_id LEFT JOIN dds.dim_date d ON d.date_key=f.date_key LEFT JOIN dds.dim_location p ON p.location_key=f.pu_location_key LEFT JOIN dds.dim_location q ON q.location_key=f.do_location_key WHERE f.period_key=:k AND (s.stg_trip_id IS NULL OR s.source_file<>:sf OR d.date_key IS NULL OR p.location_key IS NULL OR q.location_key IS NULL)'''), params).scalar()
    checks = {'log_counts': log is not None and tuple(log)==(stg[0]+rejects,stg[0],rejects), 'fact_count': stg[0]==fact[0], 'revenue': stg[1]==fact[1], 'non_null_revenue_count': stg[2]==fact[2], 'unique_fact': dup==0, 'references': bad==0, 'fact_control': is_period_loaded(engine,'fact_trip',period_key)}
    result = {'period_key':period_key,'staging_rows':stg[0],'reject_rows':rejects,'fact_rows':fact[0],'staging_revenue':str(stg[1]),'fact_revenue':str(fact[1]),'checks':checks}
    print(result)
    if not all(checks.values()):
        raise RuntimeError(f'Reconciliation failed for {period_key}: {checks}')
    return result


def run_master(period_key):
    start, end = month_bounds(period_key)
    data = Path(os.getenv('DATA_DIR','data/source'))
    for name in ('taxi_zone_lookup.csv', f'yellow_tripdata_{period_key}.parquet'):
        if not (data/name).is_file():
            raise FileNotFoundError(data/name)
    engine = get_engine()
    # Serialize master runs across processes; standalone pipelines must not run concurrently.
    with engine.connect() as lock:
        code = lock.execute(text("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'nyc_taxi_master', @LockMode='Exclusive', @LockOwner='Session', @LockTimeout=0; SELECT @r")).scalar()
        lock.commit()
        if code is None or code < 0:
            raise RuntimeError('Another master run is active')
        try:
            with engine.connect() as c:
                calendar = c.execute(text('SELECT COUNT(*) FROM dds.dim_date WHERE full_date>=:d1 AND full_date<:d2'), {'d1':start,'d2':end}).scalar()
            if calendar != (end-start).days:
                raise RuntimeError('Missing dates. Run sql/03_dds/03_dds_tables.sql first')
            if is_period_loaded(engine,'fact_trip',period_key) and not is_period_loaded(engine,'yellow_trip',period_key):
                raise RuntimeError('Fact marked Success but staging is not; investigate controls before retry')
            zones = clean_zone(load_zone_csv())
            if len(zones)!=265 or set(zones.location_id)!=set(range(1,266)):
                raise ValueError('Invalid Taxi Zones lookup')
            export_stg_taxi_zone(zones)
            load_yellow_trip_to_staging(period_key=period_key)
            sync_dim_location()
            export_fact_trip(period_key=period_key)
            return reconcile(engine, period_key)
        finally:
            lock.execute(text("EXEC sys.sp_releaseapplock @Resource=N'nyc_taxi_master', @LockOwner='Session'"))
            lock.commit()


def run_available():
    """Scheduled mode: process local files with valid names, oldest first.
    Never assumes a month is published or downloads a partial file.
    """
    import re
    data = Path(os.getenv('DATA_DIR','data/source'))
    if not data.is_dir():
        raise FileNotFoundError(data)
    periods = []
    for f in sorted(data.glob('yellow_tripdata_*.parquet')):
        m = re.fullmatch(r'yellow_tripdata_(\d{4}-\d{2})\.parquet',f.name)
        if m:
            month_bounds(m[1])
            periods.append(m[1])
    engine = get_engine()
    pending = [p for p in periods if not (is_period_loaded(engine,'yellow_trip',p) and is_period_loaded(engine,'fact_trip',p))]
    return {'mode':'auto','checks':{'all_pending_completed':True},'results':[run_master(p) for p in pending], 'skipped':len(periods)-len(pending)}
