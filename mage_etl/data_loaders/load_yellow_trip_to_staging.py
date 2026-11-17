"""
Pipeline block: Nap Trip vao Staging (Parquet -> stg.yellow_trip & stg.yellow_trip_reject).
Nguoi phu trach: Hieu

Chuc nang:
1. Doc tung tep Parquet theo tung khoi nho (chunk_size: 100.000 dong) de khong tran RAM.
2. Chuan hoa ten cot snake_case va kieu du lieu thong nhat cho moi nam.
3. Kiem tra quy tac lam sach G9:
   - dropoff_datetime <= pickup_datetime -> REJECT
   - duration > 24h -> REJECT
   - pickup_datetime nam ngoai ky nap -> REJECT
   - fare_amount < 0 hoac total_amount < 0 hoac total_amount > 1000 -> REJECT
   - datetime NULL hoac khong hop le -> REJECT
4. Nap ban ghi hop le vao stg.yellow_trip.
5. Nap ban ghi vi pham vao stg.yellow_trip_reject kem ma loi reject_reason.
6. Ghi log batch bang ham cua Hao (meta.etl_batch, meta.etl_load_control, meta.etl_error_log).
7. Tu dong bo qua thang da nap thanh cong truoc do (idempotent).
"""
import glob
import os
import re
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from sqlalchemy import text

from mage_etl.utils.etl_common import (
    get_engine,
    start_batch,
    end_batch,
    log_error,
    is_period_loaded,
    mark_period_loaded,
)

if 'data_loader' not in globals():
    from mage_ai.data_preparation.decorators import data_loader

COL_MAP = {
    'VendorID': 'vendor_id',
    'tpep_pickup_datetime': 'pickup_datetime',
    'tpep_dropoff_datetime': 'dropoff_datetime',
    'passenger_count': 'passenger_count',
    'trip_distance': 'trip_distance',
    'RatecodeID': 'rate_code_id',
    'store_and_fwd_flag': 'store_and_fwd_flag',
    'PULocationID': 'pu_location_id',
    'DOLocationID': 'do_location_id',
    'payment_type': 'payment_type',
    'fare_amount': 'fare_amount',
    'extra': 'extra',
    'mta_tax': 'mta_tax',
    'tip_amount': 'tip_amount',
    'tolls_amount': 'tolls_amount',
    'improvement_surcharge': 'improvement_surcharge',
    'total_amount': 'total_amount',
    'congestion_surcharge': 'congestion_surcharge',
    'Airport_fee': 'airport_fee',
    'airport_fee': 'airport_fee',
    'cbd_congestion_fee': 'cbd_congestion_fee',
}

STAGING_COLS = [
    'vendor_id', 'pickup_datetime', 'dropoff_datetime', 'passenger_count',
    'trip_distance', 'rate_code_id', 'store_and_fwd_flag', 'pu_location_id',
    'do_location_id', 'payment_type', 'fare_amount', 'extra', 'mta_tax',
    'tip_amount', 'tolls_amount', 'improvement_surcharge', 'total_amount',
    'congestion_surcharge', 'airport_fee', 'cbd_congestion_fee',
    'batch_id', 'source_file', 'source_row_number'
]

INT_COLS = {
    'vendor_id': 'Int16',
    'passenger_count': 'Int16',
    'rate_code_id': 'Int16',
    'pu_location_id': 'Int32',
    'do_location_id': 'Int32',
    'payment_type': 'Int16',
}

NUMERIC_COLS = [
    'trip_distance', 'fare_amount', 'extra', 'mta_tax', 'tip_amount',
    'tolls_amount', 'improvement_surcharge', 'total_amount',
    'congestion_surcharge', 'airport_fee', 'cbd_congestion_fee'
]


def process_chunk(df, period_key, batch_id, source_file, start_row):
    """Chuan hoa du lieu va kiem tra quy tac G9 tren mot khoi (chunk)."""
    df = df.rename(columns=COL_MAP).reset_index(drop=True)

    # Xu ly cac cot phu phi vang mat o cac nam cu
    for col in ['congestion_surcharge', 'airport_fee', 'cbd_congestion_fee']:
        if col not in df.columns:
            df[col] = 0.0
        else:
            df[col] = df[col].fillna(0.0)

    # Chuan hoa datetime
    df['pickup_datetime'] = pd.to_datetime(df['pickup_datetime'], errors='coerce')
    df['dropoff_datetime'] = pd.to_datetime(df['dropoff_datetime'], errors='coerce')

    # Chuan hoa numeric
    for col in NUMERIC_COLS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').round(2)

    # Chuan hoa integer nullable
    for col, dtype in INT_COLS.items():
        if col in df.columns:
            df[col] = df[col].astype(dtype)

    # Chuan hoa store_and_fwd_flag
    if 'store_and_fwd_flag' in df.columns:
        df['store_and_fwd_flag'] = df['store_and_fwd_flag'].astype(str).str.strip().str.upper()
        df.loc[df['store_and_fwd_flag'].isin(['NAN', 'NONE', '<NA>', '']), 'store_and_fwd_flag'] = None
        df['store_and_fwd_flag'] = df['store_and_fwd_flag'].str[:1]

    # Gan metadata
    df['batch_id'] = batch_id
    df['source_file'] = source_file
    df['source_row_number'] = np.arange(start_row, start_row + len(df), dtype=np.int64)

    # KIEM TRA QUY TAC G9
    period_start = pd.Timestamp(f"{period_key}-01")
    period_end = period_start + pd.DateOffset(months=1)

    reasons = np.array([""] * len(df), dtype=object)

    # 1. Datetime null / loi parse
    mask_null_time = df['pickup_datetime'].isna() | df['dropoff_datetime'].isna()
    reasons = np.where(mask_null_time, reasons + "INVALID_DATETIME;", reasons)

    # Cac kiem tra tren datetime hop le
    valid_time = ~mask_null_time
    if valid_time.any():
        vt_pickup = df.loc[valid_time, 'pickup_datetime']
        vt_dropoff = df.loc[valid_time, 'dropoff_datetime']

        # 2. Dropoff <= Pickup
        m_dropoff_le = vt_dropoff <= vt_pickup
        reasons[m_dropoff_le.index[m_dropoff_le]] += "DROPOFF_LE_PICKUP;"

        # 3. Duration > 24h
        dur_sec = (vt_dropoff - vt_pickup).dt.total_seconds()
        m_dur_24h = dur_sec > 86400
        reasons[m_dur_24h.index[m_dur_24h]] += "DURATION_EXCEEDS_24H;"

        # 4. Ngoai ky nap
        m_out = (vt_pickup < period_start) | (vt_pickup >= period_end)
        reasons[m_out.index[m_out]] += "OUT_OF_PERIOD;"

    # 5. fare_amount < 0
    m_neg_fare = df['fare_amount'].notna() & (df['fare_amount'] < 0)
    reasons = np.where(m_neg_fare, reasons + "NEGATIVE_FARE;", reasons)

    # 6. total_amount < 0 hoac > 1000
    m_bad_total = df['total_amount'].notna() & ((df['total_amount'] < 0) | (df['total_amount'] > 1000))
    reasons = np.where(m_bad_total, reasons + "INVALID_TOTAL_AMOUNT;", reasons)

    # 7. trip_distance <= 0 hoac NULL (Quy tac muc I.4: quang duong <= 0)
    m_bad_dist = df['trip_distance'].isna() | (df['trip_distance'] <= 0)
    reasons = np.where(m_bad_dist, reasons + "DISTANCE_LE_ZERO;", reasons)

    reject_mask = reasons != ""
    cleaned_reasons = pd.Series(reasons, index=df.index).str.rstrip(';')

    valid_df = df.loc[~reject_mask, STAGING_COLS].copy()
    reject_df = df.loc[reject_mask, STAGING_COLS].copy()
    reject_df['reject_reason'] = cleaned_reasons[reject_mask]

    return valid_df, reject_df


@data_loader
def load_yellow_trip_to_staging(*args, **kwargs):
    """Duyet tat ca tep Parquet trong DATA_DIR, nap vao Staging theo tung chunk."""
    data_dir = os.getenv('DATA_DIR', 'data/source')
    chunk_size = int(os.getenv('CHUNK_SIZE', '100000'))
    engine = get_engine()

    parquet_files = sorted(glob.glob(os.path.join(data_dir, 'yellow_tripdata_*.parquet')))
    period = kwargs.get("period_key")
    if period:
        parquet_files = [f for f in parquet_files if os.path.basename(f) == f"yellow_tripdata_{period}.parquet"]
    if not parquet_files and period:
        raise FileNotFoundError(f"Missing Parquet for {period}")
    if not parquet_files:
        print(f"Khong tim thay tep Parquet nao trong {data_dir}")
        return {"status": "No files found", "data_dir": data_dir}

    summary = {}

    for file_path in parquet_files:
        filename = os.path.basename(file_path)
        match = re.search(r'(\d{4}-\d{2})', filename)
        if not match:
            print(f"Bo qua file khong dung dinh dang ten: {filename}")
            continue
        period_key = match.group(1)

        # 1. Kiem tra da nap chua (idempotency)
        if is_period_loaded(engine, 'yellow_trip', period_key):
            print(f"[{period_key}] Thang da duoc nap thanh cong truoc do -> BO QUA.")
            summary[period_key] = {"status": "Skipped", "file": filename}
            continue

        print(f"\n==================================================")
        print(f"Bat dau nap: {filename} (Ky: {period_key})")
        print(f"==================================================")

        # 2. Khoi tao batch trong meta.etl_batch
        batch_id = start_batch(
            engine,
            pipeline_name='load_yellow_trip',
            layer='Staging',
            target_table='stg.yellow_trip',
            period_key=period_key,
        )

        try:
            # Xoa du lieu cu cua file nay neu lan chay truoc do bi loi
            with engine.begin() as conn:
                conn.execute(
                    text("DELETE FROM stg.yellow_trip WHERE source_file = :sf"),
                    {"sf": filename},
                )
                conn.execute(
                    text("DELETE FROM stg.yellow_trip_reject WHERE source_file = :sf"),
                    {"sf": filename},
                )

            pf = pq.ParquetFile(file_path)
            required = set(STAGING_COLS[:-3]) - {"congestion_surcharge", "airport_fee", "cbd_congestion_fee"}
            missing = required - {COL_MAP.get(c, c) for c in pf.schema_arrow.names}
            if missing:
                raise ValueError(f"Unsupported source schema: missing {sorted(missing)}")
            total_file_rows = pf.metadata.num_rows
            if not total_file_rows:
                raise ValueError("Empty source file")
            print(f"Tong so dong trong tep: {total_file_rows:,} dong (Doc theo khoi {chunk_size:,} dong)")

            file_read = 0
            file_loaded = 0
            file_rejected = 0
            row_offset = 0

            for batch in pf.iter_batches(batch_size=chunk_size):
                chunk_df = batch.to_pandas()
                n_chunk = len(chunk_df)
                file_read += n_chunk

                valid_df, reject_df = process_chunk(
                    chunk_df,
                    period_key=period_key,
                    batch_id=batch_id,
                    source_file=filename,
                    start_row=row_offset,
                )

                # Nap cac dong hop le vao stg.yellow_trip
                if len(valid_df) > 0:
                    valid_df.to_sql(
                        'yellow_trip',
                        engine,
                        schema='stg',
                        if_exists='append',
                        index=False,
                        chunksize=5000,
                    )
                    file_loaded += len(valid_df)

                # Nap cac dong loi vao stg.yellow_trip_reject
                if len(reject_df) > 0:
                    reject_df.to_sql(
                        'yellow_trip_reject',
                        engine,
                        schema='stg',
                        if_exists='append',
                        index=False,
                        chunksize=5000,
                    )
                    file_rejected += len(reject_df)

                row_offset += n_chunk
                pct = (file_read / total_file_rows) * 100
                print(f"  -> Tien do: {file_read:,}/{total_file_rows:,} ({pct:.1f}%) | Loaded: {file_loaded:,} | Rejected: {file_rejected:,}")

            # 3. Ghi ket qua thanh cong vao metadata
            end_batch(
                engine,
                batch_id,
                'Success',
                rows_read=file_read,
                rows_loaded=file_loaded,
                rows_rejected=file_rejected,
            )
            mark_period_loaded(engine, 'yellow_trip', period_key, batch_id, 'Success')

            print(f"Hoan thanh nap {filename}: Read={file_read:,}, Loaded={file_loaded:,}, Rejected={file_rejected:,}")
            summary[period_key] = {
                "status": "Success",
                "rows_read": file_read,
                "rows_loaded": file_loaded,
                "rows_rejected": file_rejected,
            }

        except Exception as e:
            print(f"LOI KHI NAP {filename}: {e}")
            log_error(engine, batch_id, 'load_yellow_trip', e)
            end_batch(engine, batch_id, 'Failed', message=str(e)[:4000])
            mark_period_loaded(engine, 'yellow_trip', period_key, batch_id, 'Failed')
            raise e

    return summary
