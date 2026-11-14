"""
Tai du lieu nguon tu TLC ve data/source (khong dua len GitHub).

Vi du:
    python scripts/download_data.py                      # mac dinh: 2024-01 va 2025-01 + zones
    python scripts/download_data.py --months 2024-01 2024-02 2025-01
Neu tai tu dong bi loi mang, tai thu cong tu trang TLC Trip Record Data va dat file vao data/source.
"""
import argparse
from pathlib import Path

import requests

BASE = "https://d37ci6vzurychx.cloudfront.net"


def download(url, dest):
    dest = Path(dest)
    if dest.exists():
        print("Bo qua (da co):", dest.name)
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print("Tai:", url)
    with requests.get(url, stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--months", nargs="*", default=["2024-01", "2025-01"], help="dang yyyy-MM")
    ap.add_argument("--out", default="data/source")
    a = ap.parse_args()

    out = Path(a.out)
    for m in a.months:
        download(f"{BASE}/trip-data/yellow_tripdata_{m}.parquet", out / f"yellow_tripdata_{m}.parquet")
    download(f"{BASE}/misc/taxi_zone_lookup.csv", out / "taxi_zone_lookup.csv")
    download(f"{BASE}/misc/taxi_zones.zip", out / "taxi_zones.zip")
    print("Xong.")


if __name__ == "__main__":
    main()
