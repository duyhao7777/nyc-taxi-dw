from sqlalchemy import text
from mage_etl.utils.etl_common import get_engine, start_batch, end_batch, log_error

if 'data_exporter' not in globals():
    from mage_ai.data_preparation.decorators import data_exporter

MERGE_SQL = """
MERGE dds.dim_location AS t
USING stg.taxi_zone AS s ON t.location_id = s.location_id
WHEN MATCHED AND EXISTS (
    SELECT s.borough, s.zone, s.service_zone
    EXCEPT
    SELECT t.borough, t.zone, t.service_zone)
    THEN UPDATE SET borough = s.borough, zone = s.zone, service_zone = s.service_zone
WHEN NOT MATCHED BY TARGET
    THEN INSERT (location_id, borough, zone, service_zone)
         VALUES (s.location_id, s.borough, s.zone, s.service_zone);
"""

@data_exporter
def sync_dim_location(*args, **kwargs):
    engine = get_engine()
    batch_id = start_batch(engine, 'load_dds', 'DDS', 'dds.dim_location')
    try:
        with engine.begin() as conn:
            total = conn.execute(text(
                "SELECT COUNT(*) FROM stg.taxi_zone")).scalar()
            conn.execute(text(MERGE_SQL))
            loaded = conn.execute(text(
                "SELECT COUNT(*) FROM dds.dim_location "
                "WHERE location_id <> -1")).scalar()
        end_batch(engine, batch_id, 'Success',
                  rows_read=total, rows_loaded=loaded)
    except Exception as e:
        log_error(engine, batch_id, 'sync_dim_location', e)
        end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
        raise