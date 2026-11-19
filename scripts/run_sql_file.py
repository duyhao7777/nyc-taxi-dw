"""Chay 1 file .sql (tach batch theo GO) truc SQL Server.

Dung trong container mage-taxi (co pyodbc san):
    docker exec mage-taxi python /home/src/scripts/run_sql_file.py sql/03_dds/03_dds_tables.sql

Bien moi truong can dung (da co san trong container):
    DB_SERVER, DB_USER, DB_PASSWORD, DB_DRIVER
"""
import os
import sys

import pyodbc


def split_batches(text):
    """Tach file .sql thanh cac batch theo dong 'GO' (nhu SSMS/sqlcmd)."""
    batches, cur = [], []
    for line in text.splitlines():
        if line.strip().upper() == 'GO':
            batches.append('\n'.join(cur))
            cur = []
        else:
            cur.append(line)
    if any(l.strip() for l in cur):
        batches.append('\n'.join(cur))
    return batches


def main():
    if len(sys.argv) < 2:
        print('Dung: python scripts/run_sql_file.py <duong-dan-file.sql>')
        sys.exit(1)
    path = sys.argv[1]
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()

    driver = os.getenv('DB_DRIVER', 'ODBC Driver 18 for SQL Server')
    server = os.getenv('DB_SERVER', 'localhost')
    user = os.getenv('DB_USER', 'sa')
    pwd = os.getenv('DB_PASSWORD', '')
    conn_str = (
        f"DRIVER={{{driver}}};SERVER={server};DATABASE=master;"
        f"UID={user};PWD={pwd};TrustServerCertificate=yes;"
    )
    conn = pyodbc.connect(conn_str, timeout=30, autocommit=True)
    cursor = conn.cursor()

    n_ok = 0
    for i, batch in enumerate(split_batches(text), 1):
        if not batch.strip():
            continue
        first = next((l.strip() for l in batch.splitlines() if l.strip() and not l.strip().startswith('--')), '')
        try:
            cursor.execute(batch)
            n_ok += 1
            print(f'[OK  ] batch {i:>2}: {first[:90]}')
            # 1 batch co the tra ve nhieu bang ket qua lien tiep -> in het
            while True:
                if cursor.description:
                    rows = cursor.fetchall()
                    cols = [d[0] for d in cursor.description]
                    if rows:
                        print('       ' + ' | '.join(cols))
                        for r in rows:
                            print('       ' + ' | '.join('' if v is None else str(v) for v in r))
                        print(f'       -> {len(rows)} dong')
                    else:
                        print('       -> (0 dong)')
                try:
                    if not cursor.nextset():
                        break
                except Exception:
                    break
        except Exception as e:
            print(f'[FAIL] batch {i:>2}: {first[:90]}')
            print('       ', str(e)[:600])
            sys.exit(1)
    print(f'Xong {path}: {n_ok} batch thanh cong.')


if __name__ == '__main__':
    main()
