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
            if conn.execute(text('SELECT COUNT(*) FROM stg.taxi_zone')).scalar() != 265:
                raise ValueError('Expected 265 staging zones')
            conn.execute(text("""UPDATE d SET borough=s.borough, zone=s.zone, service_zone=s.service_zone
                FROM dds.dim_location d JOIN stg.taxi_zone s ON d.location_id=s.location_id"""))
            conn.execute(text("""INSERT INTO dds.dim_location (location_id, borough, zone, service_zone)
                SELECT s.location_id,s.borough,s.zone,s.service_zone FROM stg.taxi_zone s
                WHERE NOT EXISTS (SELECT 1 FROM dds.dim_location d WHERE d.location_id=s.location_id)"""))
        end_batch(engine, batch_id, 'Success', rows_read=265, rows_loaded=265)
    except Exception as e:
        log_error(engine, batch_id, 'sync_dim_location', e)
        end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
        raise
