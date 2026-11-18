from sqlalchemy import text
from mage_etl.utils.etl_common import (get_engine, start_batch, end_batch,
    log_error, is_period_loaded, mark_period_loaded)

from datetime import date

# 8 dimension cua GĐ1: ten bang -> so dong toi thieu
DIMS = {
    'dds.dim_date': 1,
    'dds.dim_time': 1440,
    'dds.dim_location': 266,
    'dds.dim_vendor': 5,
    'dds.dim_payment_type': 8,
    'dds.dim_rate_code': 8,
    'dds.dim_passenger_group': 4,
    'dds.dim_distance_band': 6,
}
# dim_location duoc nap boi chinh pipeline (sync_dim_location) nen khong kiem tra truoc khi chay.
STATIC_DIMS = {k: v for k, v in DIMS.items() if k != 'dds.dim_location'}

SQL = '''
INSERT INTO dds.fact_trip (stg_trip_id, pickup_datetime, dropoff_datetime,
  date_key, dropoff_date_key, pu_location_key, do_location_key,
  pickup_time_key, dropoff_time_key,
  vendor_key, payment_key, rate_code_key, passenger_group_key, distance_band_key,
  trip_count, trip_duration,
  vendor_id, rate_code_id, payment_type,
  passenger_count, trip_distance, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
  improvement_surcharge, total_amount, congestion_surcharge, airport_fee,
  cbd_congestion_fee, batch_id, period_key)
SELECT s.stg_trip_id, s.pickup_datetime, s.dropoff_datetime,
  YEAR(s.pickup_datetime)*10000+MONTH(s.pickup_datetime)*100+DAY(s.pickup_datetime),
  dd.date_key,
  COALESCE(pu.location_key, u.location_key), COALESCE(dl.location_key, u.location_key),
  DATEPART(HOUR, s.pickup_datetime)*60+DATEPART(MINUTE, s.pickup_datetime)+1,
  DATEPART(HOUR, s.dropoff_datetime)*60+DATEPART(MINUTE, s.dropoff_datetime)+1,
  COALESCE(v.vendor_key, vu.vendor_key),
  COALESCE(pt.payment_key, ptu.payment_key),
  COALESCE(rc.rate_code_key, rcu.rate_code_key),
  COALESCE(pg.passenger_group_key, pgu.passenger_group_key),
  COALESCE(db.distance_band_key, dbu.distance_band_key),
  1,
  DATEDIFF(MINUTE, s.pickup_datetime, s.dropoff_datetime),
  s.vendor_id, s.rate_code_id, s.payment_type, s.passenger_count, s.trip_distance,
  s.fare_amount, s.extra, s.mta_tax, s.tip_amount, s.tolls_amount,
  s.improvement_surcharge, s.total_amount, s.congestion_surcharge, s.airport_fee,
  s.cbd_congestion_fee, :b, :k
FROM stg.yellow_trip s
LEFT JOIN dds.dim_date dd ON dd.date_key =
  YEAR(s.dropoff_datetime)*10000+MONTH(s.dropoff_datetime)*100+DAY(s.dropoff_datetime)
LEFT JOIN dds.dim_location pu ON pu.location_id = s.pu_location_id
LEFT JOIN dds.dim_location dl ON dl.location_id = s.do_location_id
LEFT JOIN dds.dim_vendor v ON v.vendor_code = s.vendor_id
LEFT JOIN dds.dim_payment_type pt ON pt.payment_code = s.payment_type
LEFT JOIN dds.dim_rate_code rc ON rc.rate_code_id = s.rate_code_id
LEFT JOIN dds.dim_passenger_group pg ON pg.group_name = CASE
  WHEN s.passenger_count IS NULL OR s.passenger_count = 0 OR s.passenger_count > 6 THEN 'Unknown'
  WHEN s.passenger_count = 1 THEN 'Single_passenger'
  WHEN s.passenger_count BETWEEN 2 AND 4 THEN 'Small_group'
  ELSE 'Large_group' END
LEFT JOIN dds.dim_distance_band db ON db.band_name = CASE
  WHEN s.trip_distance IS NULL OR s.trip_distance <= 0 OR s.trip_distance > 100 THEN 'Invalid'
  WHEN s.trip_distance < 1 THEN 'Under 1 mile'
  WHEN s.trip_distance < 3 THEN '1 to 3 miles'
  WHEN s.trip_distance < 7 THEN '3 to 7 miles'
  WHEN s.trip_distance < 15 THEN '7 to 15 miles'
  ELSE '15 miles and up' END
CROSS JOIN (SELECT location_key FROM dds.dim_location WHERE location_id = -1) u
CROSS JOIN (SELECT vendor_key FROM dds.dim_vendor WHERE vendor_code = -1) vu
CROSS JOIN (SELECT payment_key FROM dds.dim_payment_type WHERE payment_code = -1) ptu
CROSS JOIN (SELECT rate_code_key FROM dds.dim_rate_code WHERE rate_code_id = -1) rcu
CROSS JOIN (SELECT passenger_group_key FROM dds.dim_passenger_group WHERE group_name = 'Unknown') pgu
CROSS JOIN (SELECT distance_band_key FROM dds.dim_distance_band WHERE band_name = 'Invalid') dbu
WHERE s.pickup_datetime >= :d1 AND s.pickup_datetime < :d2
'''

if 'data_exporter' not in globals():
    from mage_ai.data_preparation.decorators import data_exporter


def check_dims(conn, tables=None):
    """Fail fast neu dimension chua nap day du (chay 03_dds_tables.sql truoc)."""
    targets = DIMS if tables is None else tables
    problems = []
    for table, minimum in targets.items():
        n = conn.execute(text(f'SELECT COUNT(*) FROM {table}')).scalar()
        if n is None or n < minimum:
            problems.append(f'{table}={n} (can >= {minimum})')
    if problems:
        raise RuntimeError('DDS dimensions not ready: ' + '; '.join(problems)
                           + '. Run sql/03_dds/03_dds_tables.sql first')


@data_exporter
def export_fact_trip(*args, **kwargs):
    engine = get_engine()
    period = kwargs.get('period_key')
    with engine.connect() as conn:
        check_dims(conn)
        periods = [r[0].strip() for r in conn.execute(text("SELECT period_key FROM meta.etl_load_control WHERE dataset='yellow_trip' AND status='Success' ORDER BY period_key"))]
    if period:
        if period not in periods:
            raise ValueError(f'Staging not successful for {period}')
        periods = [period]
    for k in periods:
        d1 = date.fromisoformat(k + '-01')
        d2 = date(d1.year + (d1.month == 12), d1.month % 12 + 1, 1)
        if is_period_loaded(engine, 'fact_trip', k):
            print('Bo qua (da nap):', k)
            continue
        batch_id = start_batch(engine, 'load_dds', 'DDS', 'dds.fact_trip', period_key=k)
        try:
            with engine.begin() as conn:
                expected = conn.execute(text('SELECT COUNT_BIG(*) FROM stg.yellow_trip WHERE pickup_datetime >= :d1 AND pickup_datetime < :d2'), {'d1': d1, 'd2': d2}).scalar()
                conn.execute(text('DELETE FROM dds.fact_trip WHERE period_key = :k'), {'k': k})
                r = conn.execute(text(SQL), {'b': batch_id, 'k': k, 'd1': d1, 'd2': d2})
                actual = conn.execute(text('SELECT COUNT_BIG(*) FROM dds.fact_trip WHERE period_key=:k'), {'k': k}).scalar()
                if actual != expected:
                    raise RuntimeError(f'Fact count {actual} != staging {expected}')
                null_dim = conn.execute(text('''SELECT COUNT_BIG(*) FROM dds.fact_trip WHERE period_key=:k AND
                    (date_key IS NULL OR pu_location_key IS NULL OR do_location_key IS NULL
                     OR pickup_time_key IS NULL OR dropoff_time_key IS NULL
                     OR vendor_key IS NULL OR payment_key IS NULL OR rate_code_key IS NULL
                     OR passenger_group_key IS NULL OR distance_band_key IS NULL
                     OR trip_count <> 1 OR trip_duration IS NULL)'''), {'k': k}).scalar()
                if null_dim:
                    raise RuntimeError(f'Fact rows with NULL dimension keys or measures: {null_dim}')
            end_batch(engine, batch_id, 'Success', rows_read=expected, rows_loaded=actual)
            mark_period_loaded(engine, 'fact_trip', k, batch_id)
        except Exception as e:
            log_error(engine, batch_id, 'export_fact_trip_' + k, e)
            end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
            mark_period_loaded(engine, 'fact_trip', k, batch_id, 'Failed')
            raise
