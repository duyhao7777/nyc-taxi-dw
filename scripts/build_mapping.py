"""Build docs/mapping.xlsx (ban nhap cho Huy chot) chi dung thu vien chuan Python.

Chay: ./.venv/bin/python scripts/build_mapping.py
"""
import datetime
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "mapping.xlsx"

NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def col_letter(i):
    s = ""
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def cell(ref, val, bold=False):
    s = ' s="1"' if bold else ""
    return f'<c r="{ref}" t="inlineStr"{s}><is><t>{escape(str(val))}</t></is></c>'


def sheet_xml(headers, rows):
    parts = [f'<worksheet xmlns="{NS}"><cols>']
    n = len(headers)
    parts.append(f'<col min="1" max="{n}" width="24" customWidth="1"/>')
    parts.append("</cols><sheetData>")
    vals = [cell(f"{col_letter(c)}1", h, True) for c, h in enumerate(headers, 1)]
    parts.append(f"<row r=\"1\">{''.join(vals)}</row>")
    for r, row in enumerate(rows, 2):
        vals = [cell(f"{col_letter(c)}{r}", v) for c, v in enumerate(row, 1)]
        parts.append(f"<row r=\"{r}\">{''.join(vals)}</row>")
    parts.append("</sheetData></worksheet>")
    return "".join(parts)


COVER = [
    ["NYC Yellow Taxi DW - Mapping Nguon -> Staging -> DDS (BAN NHAP, Huy chot)"],
    [f"Ngay tao: {datetime.date.today().isoformat()} - Nguoi tao nhap: Cuong"],
    ["Quy uoc: ten bang stg.taxi_zone, stg.yellow_trip(+_reject), dds.dim_*, dds.fact_trip; cot snake_case"],
    ["Grain fact: 1 dong fact = 1 dong stg.yellow_trip (giu check 5+6 file 05_reconcile_checks.sql PASS)"],
]

SRC_STG_H = ["File nguon", "Cot nguon", "Bang stg", "Cot stg", "Kieu SQL", "Quy tac / Ghi chu"]
SRC_STG = [
    ["taxi_zone_lookup.csv", "LocationID", "stg.taxi_zone", "location_id", "INT PK", "Khoa chinh, 265 dong"],
    ["taxi_zone_lookup.csv", "Borough", "stg.taxi_zone", "borough", "NVARCHAR(50)", "Giu nguyen"],
    ["taxi_zone_lookup.csv", "Zone", "stg.taxi_zone", "zone", "NVARCHAR(100)", "Giu nguyen"],
    ["taxi_zone_lookup.csv", "service_zone", "stg.taxi_zone", "service_zone", "NVARCHAR(50)", "Giu nguyen"],
    ["yellow_tripdata_*.parquet", "(system)", "stg.yellow_trip", "stg_trip_id", "BIGINT IDENTITY PK", "Khoa tu tang"],
    ["yellow_tripdata_*.parquet", "VendorID", "stg.yellow_trip", "vendor_id", "SMALLINT", "snake_case"],
    ["yellow_tripdata_*.parquet", "tpep_pickup_datetime", "stg.yellow_trip", "pickup_datetime", "DATETIME2(0)", "Chuan hoa ten"],
    ["yellow_tripdata_*.parquet", "tpep_dropoff_datetime", "stg.yellow_trip", "dropoff_datetime", "DATETIME2(0)", "Chuan hoa ten"],
    ["yellow_tripdata_*.parquet", "passenger_count", "stg.yellow_trip", "passenger_count", "TINYINT", ""],
    ["yellow_tripdata_*.parquet", "trip_distance", "stg.yellow_trip", "trip_distance", "DECIMAL(10,2)", "Vi pham G9 -> reject"],
    ["yellow_tripdata_*.parquet", "RatecodeID", "stg.yellow_trip", "rate_code_id", "SMALLINT", ""],
    ["yellow_tripdata_*.parquet", "store_and_fwd_flag", "stg.yellow_trip", "store_and_fwd_flag", "CHAR(1)", ""],
    ["yellow_tripdata_*.parquet", "PULocationID", "stg.yellow_trip", "pu_location_id", "INT", "FK -> dim_location"],
    ["yellow_tripdata_*.parquet", "DOLocationID", "stg.yellow_trip", "do_location_id", "INT", "FK -> dim_location"],
    ["yellow_tripdata_*.parquet", "payment_type", "stg.yellow_trip", "payment_type", "SMALLINT", "Degenerate dim"],
    ["yellow_tripdata_*.parquet", "fare_amount", "stg.yellow_trip", "fare_amount", "DECIMAL(10,2)", "Am -> reject"],
    ["yellow_tripdata_*.parquet", "extra/mta_tax/tip/tolls/improvement", "stg.yellow_trip", "(gi nguyen ten)", "DECIMAL(10,2)", "snake_case"],
    ["yellow_tripdata_*.parquet", "total_amount", "stg.yellow_trip", "total_amount", "DECIMAL(10,2)", "Am/>1000 -> reject"],
    ["yellow_tripdata_*.parquet", "congestion_surcharge/Airport_fee (+cbd 2025)", "stg.yellow_trip", "(gi nguyen ten)", "DECIMAL(10,2) DEFAULT 0", "Cot moi nam sau default 0"],
    ["(cac ban G9)", "(vi pham I.4)", "stg.yellow_trip_reject", "(toan bo cot + reject_reason)", "VARCHAR(255)", "Ma loi noi bang ';'"],
]

STG_DDS_H = ["Bang stg", "Cot stg", "Bang dds", "Cot dds", "Kieu SQL", "Quy tac / Ghi chu"]
STG_DDS = [
    ["stg.taxi_zone", "location_id", "dds.dim_location", "location_id", "INT UNIQUE", "Khoa tu nhien 1-265"],
    ["stg.taxi_zone", "borough", "dds.dim_location", "borough", "NVARCHAR(50)", "SCD1 (ghi de)"],
    ["stg.taxi_zone", "zone", "dds.dim_location", "zone", "NVARCHAR(100)", "SCD1"],
    ["stg.taxi_zone", "service_zone", "dds.dim_location", "service_zone", "NVARCHAR(50)", "SCD1"],
    ["(system)", "(system)", "dds.dim_location", "location_key", "INT IDENTITY PK", "Khoa thay the + dong Unknown"],
    ["(sinh san)", "(sinh san 2024-2026)", "dds.dim_date", "date_key/type fields", "INT yyyymmdd PK", "Dim lich: year/quarter/month/day/is_weekend"],
    ["stg.yellow_trip", "stg_trip_id", "dds.fact_trip", "stg_trip_id", "BIGINT", "Truy vet nguon"],
    ["stg.yellow_trip", "pickup/dropoff_datetime", "dds.fact_trip", "pickup/dropoff_datetime + date_key", "DATETIME2(0)/INT", "date_key tu pickup_datetime"],
    ["stg.yellow_trip", "pu/do_location_id", "dds.fact_trip", "pu/do_location_key", "INT FK", "Join dim_location theo location_id"],
    ["stg.yellow_trip", "vendor_id/rate_code_id/payment_type", "dds.fact_trip", "(gi nguyen)", "SMALLINT", "Degenerate dimension"],
    ["stg.yellow_trip", "passenger_count/trip_distance", "dds.fact_trip", "(gi nguyen)", "TINYINT/DECIMAL(10,2)", "Measure"],
    ["stg.yellow_trip", "fare/extra/mta_tax/tip/tolls/improvement/total/congestion/airport/cbd", "dds.fact_trip", "(gi nguyen)", "DECIMAL(10,2)", "Measure, giu total_amount de doi soat check 6"],
    ["meta.etl_batch", "batch_id", "dds.fact_trip", "batch_id + period_key", "INT/CHAR(7)", "Truy vet lan nap theo thang"],
]

REJECT_H = ["Ma loi (reject_reason)", "Dieu kien vi pham", "Y nghia"]
REJECT = [
    ["DROPOFF_LE_PICKUP", "dropoff_datetime <= pickup_datetime", "Tra truoc/bang don"],
    ["DURATION_EXCEEDS_24H", "(dropoff - pickup) > 24 gio", "Chuyen di bat thuong"],
    ["DISTANCE_LE_ZERO", "trip_distance <= 0 hoac NULL", "Quang duong am/zero"],
    ["NEGATIVE_FARE", "fare_amount < 0", "Cuoc am"],
    ["INVALID_TOTAL_AMOUNT", "total_amount < 0 hoac > 1000", "Tong tien ngoai nguong"],
    ["OUT_OF_PERIOD", "pickup_datetime ngoai thang nap", "Ban ghi lac ky"],
    ["INVALID_DATETIME", "pickup/dropoff_datetime NULL", "Mat moc thoi gian"],
]

PIPE_H = ["Pipeline", "Nguon", "Dich", "Nguoi", "Trang thai"]
PIPE = [
    ["load_taxi_zones", "taxi_zone_lookup.csv", "stg.taxi_zone (265)", "Hao", "Xong"],
    ["load_yellow_trip", "yellow_tripdata_*.parquet", "stg.yellow_trip + _reject", "Hieu", "Xong"],
    ["load_dds", "stg.*", "dds.dim_* + dds.fact_trip", "Cuong", "Dang lam"],
    ["pipeline tong", "stg->dds theo thang", "toan bo", "Huy", "Chua lam"],
]

SHEETS = [
    ("Cover", ["Noi dung"], COVER),
    ("Source_Staging", SRC_STG_H, SRC_STG),
    ("Staging_DDS", STG_DDS_H, STG_DDS),
    ("Reject_Rules", REJECT_H, REJECT),
    ("Pipelines", PIPE_H, PIPE),
]

CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    + "".join(
        f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        for i in range(1, len(SHEETS) + 1)
    )
    + "</Types>"
)
RELS = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    "</Relationships>"
)
WB_RELS = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + "".join(
        f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>'
        for i in range(1, len(SHEETS) + 1)
    )
    + f'<Relationship Id="rId{len(SHEETS) + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    + "</Relationships>"
)
WORKBOOK = (
    f'<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="{NS}" xmlns:r="{REL}"><sheets>'
    + "".join(
        f'<sheet name="{n}" sheetId="{i}" r:id="rId{i}"/>' for i, (n, _, _) in enumerate(SHEETS, 1)
    )
    + "</sheets></workbook>"
)
STYLES = (
    f'<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="{NS}">'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
    "</styleSheet>"
)


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", RELS)
        z.writestr("xl/workbook.xml", WORKBOOK)
        z.writestr("xl/_rels/workbook.xml.rels", WB_RELS)
        z.writestr("xl/styles.xml", STYLES)
        for i, (_, headers, rows) in enumerate(SHEETS, 1):
            z.writestr(f"xl/worksheets/sheet{i}.xml", sheet_xml(headers, rows))
    print("Wrote", OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
