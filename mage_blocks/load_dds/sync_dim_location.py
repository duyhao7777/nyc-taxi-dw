from sqlalchemy import text
from mage_etl.utils.etl_common import get_engine, start_batch, end_batch, log_error

if 'data_exporter' not in globals():
    from mage_ai.data_preparation.decorators import data_exporter

@data_exporter
def sync_dim_location(*args, **kwargs):
    engine = get_engine()
    batch_id = start_batch(engine, 'load_dds', 'DDS', 'dds.dim_location')
    try:
        with engine.begin() as conn:
            conn.execute(text('DELETE FROM dds.dim_location WHERE location_id <> -1'))
            r = conn.execute(text(
                'INSERT INTO dds.dim_location (location_id, borough, zone, service_zone) '
                'SELECT location_id, borough, zone, service_zone FROM stg.taxi_zone'))
        end_batch(engine, batch_id, 'Success', rows_read=265, rows_loaded=r.rowcount)
    except Exception as e:
        log_error(engine, batch_id, 'sync_dim_location', e)
        end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
        raise