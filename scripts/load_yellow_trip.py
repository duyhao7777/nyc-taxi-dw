"""
Script chay truc tiep nap du lieu Yellow Taxi tu Parquet vao Staging.
Cung co the chay thong qua Mage pipeline: mage run mage_etl load_yellow_trip

Cach dung:
    python scripts/load_yellow_trip.py
    python scripts/load_yellow_trip.py --months 2024-01 2025-01
    python scripts/load_yellow_trip.py --chunk-size 100000
"""
import argparse
import glob
import os
import re
import sys
from pathlib import Path

# Them thu muc goc vao sys.path de import duoc mage_etl
ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from mage_etl.data_loaders.load_yellow_trip_to_staging import load_yellow_trip_to_staging


def main():
    parser = argparse.ArgumentParser(description="Nap du lieu Yellow Taxi Parquet vao Staging")
    parser.add_argument("--data-dir", default=os.getenv("DATA_DIR", "data/source"), help="Thu muc chua file Parquet")
    parser.add_argument("--chunk-size", type=int, default=int(os.getenv("CHUNK_SIZE", "100000")), help="So dong moi khoi")
    parser.add_argument("--months", nargs="*", default=None, help="Cac thang can nap (vi du: 2024-01 2025-01)")
    args = parser.parse_args()

    os.environ["DATA_DIR"] = args.data_dir
    os.environ["CHUNK_SIZE"] = str(args.chunk_size)

    print("==================================================")
    print("CHUONG TRINH NAP TRIP VAO STAGING (HIỆU)")
    print(f"Thư mục dữ liệu: {args.data_dir}")
    print(f"Kích thước khối (chunk size): {args.chunk_size:,} dòng")
    print("==================================================")

    res = {}
    if args.months:
        for period in args.months:
            res.update(load_yellow_trip_to_staging(period_key=period))
    else:
        res = load_yellow_trip_to_staging()
    print("\nKết quả tổng kết:")
    for k, v in res.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
