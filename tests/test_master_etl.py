"""Unit checks: no SQL Server required. Run from repo root with installed requirements."""
import unittest
from datetime import date
import pandas as pd
from mage_etl.utils.master_etl import month_bounds
from mage_etl.data_loaders.load_yellow_trip_to_staging import process_chunk

class TestRules(unittest.TestCase):
    def test_months(self):
        self.assertEqual(month_bounds('2024-02'),(date(2024,2,1),date(2024,3,1)))
        self.assertEqual(month_bounds('2025-12'),(date(2025,12,1),date(2026,1,1)))
        for bad in [None,'2025-1','2025-13','2009-01','2027-01']:
            with self.assertRaises(ValueError): month_bounds(bad)

    def test_quality(self):
        base=dict(VendorID=1,tpep_pickup_datetime='2025-01-01 10:00:00',tpep_dropoff_datetime='2025-01-01 10:10:00',passenger_count=2,trip_distance=2.5,RatecodeID=1,store_and_fwd_flag='N',PULocationID=1,DOLocationID=2,payment_type=1,fare_amount=10,extra=0,mta_tax=.5,tip_amount=2,tolls_amount=0,improvement_surcharge=1,total_amount=13.5)
        cases=[{}, {'tpep_dropoff_datetime':'2025-01-01 09:00:00'}, {'trip_distance':0,'fare_amount':-1}, {'total_amount':1000}, {'total_amount':1000.01}, {'passenger_count':None,'RatecodeID':None}, {'tpep_pickup_datetime':'2024-12-31 23:50:00'}, {'tpep_dropoff_datetime':'2025-01-02 10:00:01'}, {'tpep_dropoff_datetime':None}, {'trip_distance':101}]
        valid,rejected=process_chunk(pd.DataFrame([dict(base,**x) for x in cases]),'2025-01',7,'yellow_tripdata_2025-01.parquet',100)
        self.assertEqual(list(valid.source_row_number),[100,103,105,109])
        self.assertEqual(len(valid)+len(rejected),len(cases))
        self.assertTrue((valid.cbd_congestion_fee==0).all())
        self.assertTrue((valid.airport_fee==0).all())
        self.assertTrue((valid.congestion_surcharge==0).all())
        r=rejected.set_index('source_row_number').reject_reason
        self.assertEqual(set(r[102].split(';')),{'NEGATIVE_FARE','DISTANCE_LE_ZERO'})
        for i,reason in [(101,'DROPOFF_LE_PICKUP'),(104,'INVALID_TOTAL_AMOUNT'),(106,'OUT_OF_PERIOD'),(107,'DURATION_EXCEEDS_24H'),(108,'INVALID_DATETIME')]: self.assertIn(reason,r[i])

if __name__=='__main__': unittest.main()
