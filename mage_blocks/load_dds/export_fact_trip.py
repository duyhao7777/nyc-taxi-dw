from sqlalchemy import text
from mage_etl.utils.etl_common import (get_engine, start_batch, end_batch,
    log_error, is_period_loaded, mark_period_loaded)

MONTHS = [('2024-01', '2024-01-01', '2024-02-01'),
          ('2024-02', '2024-02-01', '2024-03-01'),
          ('2025-01', '2025-01-01', '2025-02-01')]

SQL = '''
INSERT INTO dds.fact_trip (stg_trip_id, pickup_datetime, dropoff_datetime, date_key,
  pu_location_key, do_location_key, vendor_id, rate_code_id, payment_type,
  passenger_count, trip_distance, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
  improvement_surcharge, total_amount, congestion_surcharge, airport_fee,
  cbd_congestion_fee, batch_id, period_key)
SELECT s.stg_trip_id, s.pickup_datetime, s.dropoff_datetime,
  YEAR(s.pickup_datetime)*10000+MONTH(s.pickup_datetime)*100+DAY(s.pickup_datetime),
  COALESCE(pu.location_key, u.location_key), COALESCE(dl.location_key, u.location_key),
  s.vendor_id, s.rate_code_id, s.payment_type, s.passenger_count, s.trip_distance,
  s.fare_amount, s.extra, s.mta_tax, s.tip_amount, s.tolls_amount,
  s.improvement_surcharge, s.total_amount, s.congestion_surcharge, s.airport_fee,
  s.cbd_congestion_fee, :b, :k
FROM stg.yellow_trip s
LEFT JOIN dds.dim_location pu ON pu.location_id = s.pu_location_id
LEFT JOIN dds.dim_location dl ON dl.location_id = s.do_location_id
CROSS JOIN (SELECT location_key FROM dds.dim_location WHERE location_id = -1) u
WHERE s.pickup_datetime >= :d1 AND s.pickup_datetime < :d2
'''

if 'data_exporter' not in globals():
    from mage_ai.data_preparation.decorators import data_exporter

@data_exporter
def export_fact_trip(*args, **kwargs):
    engine = get_engine()
    for k, d1, d2 in MONTHS:
        if is_period_loaded(engine, 'fact_trip', k):
            print('Bo qua (da nap):', k)
            continue
        batch_id = start_batch(engine, 'load_dds', 'DDS', 'dds.fact_trip', period_key=k)
        try:
            with engine.begin() as conn:
                conn.execute(text('DELETE FROM dds.fact_trip WHERE period_key = :k'), {'k': k})
                r = conn.execute(text(SQL), {'b': batch_id, 'k': k, 'd1': d1, 'd2': d2})
            end_batch(engine, batch_id, 'Success', rows_read=r.rowcount, rows_loaded=r.rowcount)
            mark_period_loaded(engine, 'fact_trip', k, batch_id)
        except Exception as e:
            log_error(engine, batch_id, 'export_fact_trip_' + k, e)
            end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
            raise