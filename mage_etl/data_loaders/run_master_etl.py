from mage_etl.utils.master_etl import run_master, run_available
if 'data_loader' not in globals():
    from mage_ai.data_preparation.decorators import data_loader
if 'test' not in globals():
    from mage_ai.data_preparation.decorators import test

@data_loader
def run_master_etl(*args, **kwargs):
    period = kwargs.get('period_key')
    return run_available() if period == 'auto' else run_master(period)

@test
def test_output(output, *args):
    assert all(output['checks'].values()), output
