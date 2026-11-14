# Block 2/3 - Transformer. Them block Transformer (Python > Generic), dan noi dung file nay vao.
if 'transformer' not in globals():
    from mage_ai.data_preparation.decorators import transformer
if 'test' not in globals():
    from mage_ai.data_preparation.decorators import test


@transformer
def clean_zone(df, *args, **kwargs):
    # Doi ten cot ve snake_case, thong nhat voi bang stg.taxi_zone
    df = df.rename(columns={
        'LocationID': 'location_id',
        'Borough': 'borough',
        'Zone': 'zone',
        'service_zone': 'service_zone',
    })
    for col in ['borough', 'zone', 'service_zone']:
        df[col] = df[col].astype(str).str.strip()
    df['location_id'] = df['location_id'].astype(int)
    return df[['location_id', 'borough', 'zone', 'service_zone']]


@test
def test_output(output, *args) -> None:
    assert output['location_id'].is_unique, 'location_id bi trung'
    assert len(output) == 265, f'Ky vong 265 khu vuc, thuc te {len(output)}'
# Block 2/3 - Transformer. Them block Transformer (Python > Generic), dan noi dung file nay vao.
if 'transformer' not in globals():
    from mage_ai.data_preparation.decorators import transformer
if 'test' not in globals():
    from mage_ai.data_preparation.decorators import test


@transformer
def clean_zone(df, *args, **kwargs):
    # Doi ten cot ve snake_case, thong nhat voi bang stg.taxi_zone
    df = df.rename(columns={
        'LocationID': 'location_id',
        'Borough': 'borough',
        'Zone': 'zone',
        'service_zone': 'service_zone',
    })
    for col in ['borough', 'zone', 'service_zone']:
        df[col] = df[col].astype(str).str.strip()
    df['location_id'] = df['location_id'].astype(int)
    return df[['location_id', 'borough', 'zone', 'service_zone']]


@test
def test_output(output, *args) -> None:
    assert output['location_id'].is_unique, 'location_id bi trung'
    assert len(output) == 265, f'Ky vong 265 khu vuc, thuc te {len(output)}'
