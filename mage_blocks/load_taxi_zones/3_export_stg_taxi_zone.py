# Block 3/3 - Data exporter. Them block Data exporter (Python > Generic), dan noi dung file nay vao.
# Can: bang stg.taxi_zone (sql/02_staging/02_stg_taxi_zone.sql), bang meta.* (sql/04_metadata/...),
#      file etl_common.py da copy vao mage_etl/utils/.
from sqlalchemy import text

from mage_etl.utils.etl_common import get_engine, start_batch, end_batch, log_error

if 'data_exporter' not in globals():
    from mage_ai.data_preparation.decorators import data_exporter


@data_exporter
def export_stg_taxi_zone(df, *args, **kwargs):
    engine = get_engine()
    batch_id = start_batch(engine, 'load_taxi_zones', 'Staging', 'stg.taxi_zone')
    try:
        df = df.copy()
        df['batch_id'] = batch_id
        with engine.begin() as conn:
            conn.execute(text('DELETE FROM stg.taxi_zone'))   # nap lai toan bo, chay lai nhieu lan van an toan
            df.to_sql('taxi_zone', conn, schema='stg', if_exists='append', index=False, chunksize=500)
        end_batch(engine, batch_id, 'Success', rows_read=len(df), rows_loaded=len(df))
    except Exception as e:
        log_error(engine, batch_id, 'export_stg_taxi_zone', e)
        end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
        raise
