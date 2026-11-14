"""
Ham dung chung cho cac pipeline ETL: ket noi SQL Server + ghi Metadata.

CACH DUNG:
  1) Sau khi chay `mage init mage_etl`, copy file nay vao mage_etl/utils/etl_common.py
  2) Trong block cua Mage:
       from mage_etl.utils.etl_common import get_engine, start_batch, end_batch, log_error
  3) Kiem tra ket noi (chay o thu muc goc repo):
       python mage_extras/etl_common.py

CAU HINH qua bien moi truong (PowerShell: $env:TEN="gia tri"):
  DB_SERVER    mac dinh localhost       (vi du localhost\\SQLEXPRESS)
  DB_NAME      mac dinh NYCTaxi_DW
  DB_DRIVER    mac dinh "ODBC Driver 18 for SQL Server"  (neu may cai ban 17 thi dat lai)
  DB_USER, DB_PASSWORD   neu dung SQL Server Authentication.
                         Bo trong thi dung Windows Authentication.
"""
import os
from urllib.parse import quote_plus

from sqlalchemy import create_engine, text


def get_engine():
    server = os.getenv("DB_SERVER", "localhost")
    database = os.getenv("DB_NAME", "NYCTaxi_DW")
    driver = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")
    user = os.getenv("DB_USER")
    password = os.getenv("DB_PASSWORD", "")

    parts = [
        f"DRIVER={{{driver}}}",
        f"SERVER={server}",
        f"DATABASE={database}",
        "TrustServerCertificate=yes",
    ]
    if user:
        parts += [f"UID={user}", f"PWD={password}"]
    else:
        parts.append("Trusted_Connection=yes")

    conn_str = ";".join(parts)
    return create_engine(
        "mssql+pyodbc:///?odbc_connect=" + quote_plus(conn_str),
        fast_executemany=True,
    )


def start_batch(engine, pipeline_name, layer, target_table=None, period_key=None):
    """Ghi 1 dong Running vao meta.etl_batch, tra ve batch_id."""
    sql = text(
        """
        INSERT INTO meta.etl_batch (pipeline_name, layer, target_table, period_key)
        OUTPUT INSERTED.batch_id
        VALUES (:p, :l, :t, :k)
        """
    )
    with engine.begin() as conn:
        return conn.execute(
            sql, {"p": pipeline_name, "l": layer, "t": target_table, "k": period_key}
        ).scalar()


def end_batch(engine, batch_id, status, rows_read=None, rows_loaded=None,
              rows_rejected=None, message=None):
    """Cap nhat ket qua batch: status = 'Success' hoac 'Failed'."""
    sql = text(
        """
        UPDATE meta.etl_batch
        SET end_time = SYSDATETIME(), status = :s,
            rows_read = :rr, rows_loaded = :rl, rows_rejected = :rj, message = :m
        WHERE batch_id = :b
        """
    )
    with engine.begin() as conn:
        conn.execute(
            sql,
            {"s": status, "rr": rows_read, "rl": rows_loaded,
             "rj": rows_rejected, "m": message, "b": batch_id},
        )


def log_error(engine, batch_id, step_name, error_message):
    sql = text(
        """
        INSERT INTO meta.etl_error_log (batch_id, step_name, error_message)
        VALUES (:b, :s, :m)
        """
    )
    with engine.begin() as conn:
        conn.execute(sql, {"b": batch_id, "s": step_name, "m": str(error_message)})


def is_period_loaded(engine, dataset, period_key):
    """True neu thang nay da nap thanh cong (de bo qua, khong nap lai)."""
    sql = text(
        """
        SELECT 1 FROM meta.etl_load_control
        WHERE dataset = :d AND period_key = :k AND status = N'Success'
        """
    )
    with engine.connect() as conn:
        return conn.execute(sql, {"d": dataset, "k": period_key}).first() is not None


def mark_period_loaded(engine, dataset, period_key, batch_id, status="Success"):
    sql = text(
        """
        MERGE meta.etl_load_control AS t
        USING (SELECT :d AS dataset, :k AS period_key) AS s
           ON t.dataset = s.dataset AND t.period_key = s.period_key
        WHEN MATCHED THEN
            UPDATE SET status = :st, last_batch_id = :b, loaded_at = SYSDATETIME()
        WHEN NOT MATCHED THEN
            INSERT (dataset, period_key, status, last_batch_id)
            VALUES (:d, :k, :st, :b);
        """
    )
    with engine.begin() as conn:
        conn.execute(sql, {"d": dataset, "k": period_key, "st": status, "b": batch_id})


if __name__ == "__main__":
    eng = get_engine()
    with eng.connect() as c:
        print(c.execute(text("SELECT @@VERSION")).scalar())
        rows = c.execute(
            text("SELECT name FROM sys.schemas WHERE name IN (N'stg', N'dds', N'meta')")
        ).fetchall()
        print("Schemas:", sorted(r[0] for r in rows))
    print("Ket noi OK")
