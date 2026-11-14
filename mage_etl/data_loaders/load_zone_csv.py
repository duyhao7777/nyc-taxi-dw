# Block 1/3 - Data loader. Tao pipeline "load_taxi_zones" trong Mage, them block Data loader (Python > Generic),
# roi dan noi dung file nay vao.
import os

import pandas as pd

if 'data_loader' not in globals():
    from mage_ai.data_preparation.decorators import data_loader
if 'test' not in globals():
    from mage_ai.data_preparation.decorators import test


@data_loader
def load_zone_csv(*args, **kwargs):
    # DATA_DIR: dat bien moi truong tro toi thu muc chua taxi_zone_lookup.csv (nen dung duong dan tuyet doi)
    data_dir = os.getenv('DATA_DIR', 'data/source')
    path = os.path.join(data_dir, 'taxi_zone_lookup.csv')
    # keep_default_na=False: giu nguyen chuoi 'N/A' o cot Borough (khong de pandas doi thanh null)
    return pd.read_csv(path, keep_default_na=False)


@test
def test_output(output, *args) -> None:
    assert output is not None and len(output) > 0, 'File CSV rong hoac khong doc duoc'
    assert 'LocationID' in output.columns, 'Thieu cot LocationID'
