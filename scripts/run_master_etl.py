import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mage_etl.utils.master_etl import run_master, run_available

if __name__=='__main__':
    p=argparse.ArgumentParser(description='Run full ETL for one or more months, sequentially')
    mode=p.add_mutually_exclusive_group(required=True)
    mode.add_argument('--months',nargs='+')
    mode.add_argument('--auto',action='store_true')
    args=p.parse_args()
    if args.auto:
        print(json.dumps(run_available(),ensure_ascii=False,indent=2))
        sys.exit(0)
    for month in args.months:
        print(json.dumps(run_master(month),ensure_ascii=False,indent=2))
