#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

import pytest

PARQUET_PATH = '/home/user/unified_sensors.parquet'
SCRIPT_PATH = '/home/user/process_pipeline.py'
CSV_PATH = '/home/user/inputs/factory_1.csv'
JSON_PATH = '/home/user/inputs/factory_2.json'


def normalize_timestamp(value):
    text = str(value).strip()
    if text.endswith('Z'):
        text = text[:-1] + '+00:00'
    dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')


def expected_from_inputs():
    rows = []
    with open(CSV_PATH, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames and reader.fieldnames[0] == 'timestamp'
        for source_row in reader:
            ts = normalize_timestamp(source_row['timestamp'])
            for sensor in reader.fieldnames[1:]:
                rows.append((ts, sensor.lower(), float(source_row[sensor])))

    with open(JSON_PATH, encoding='utf-8') as f:
        for source_row in json.load(f):
            rows.append((
                normalize_timestamp(source_row['time']),
                str(source_row['sensor']).lower(),
                float(source_row['reading']),
            ))

    unique = []
    seen = set()
    for ts, sensor, value in rows:
        record_hash = hashlib.md5(
            f'{ts}_{sensor}_{value:.2f}'.encode('utf-8')
        ).hexdigest()
        if record_hash not in seen:
            seen.add(record_hash)
            unique.append({
                'timestamp': ts,
                'sensor_id': sensor,
                'value': value,
                'record_hash': record_hash,
            })
    return sorted(unique, key=lambda row: (row['timestamp'], row['sensor_id']))


def run_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f'Required script not found: {SCRIPT_PATH}'
    if os.path.exists(PARQUET_PATH):
        os.remove(PARQUET_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'Pipeline execution failed with code {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert os.path.isfile(PARQUET_PATH), (
        f'Executing {SCRIPT_PATH} did not create {PARQUET_PATH}'
    )


def get_parquet_data():
    if not os.path.exists(PARQUET_PATH):
        pytest.fail(f'File not found: {PARQUET_PATH}')

    script = """
import sys
import json
try:
    import pandas as pd
    df = pd.read_parquet('/home/user/unified_sensors.parquet')
    df['timestamp'] = df['timestamp'].astype(str)
    df['sensor_id'] = df['sensor_id'].astype(str)
    df['value'] = df['value'].astype(float)
    df['record_hash'] = df['record_hash'].astype(str)
    print(df.to_json(orient='records'))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
"""
    result = subprocess.run(
        [sys.executable, '-c', script], capture_output=True, text=True
    )
    if result.returncode != 0:
        pytest.fail(
            'Failed to read parquet file. Ensure pandas and a parquet engine '
            f'(pyarrow/fastparquet) are installed. Error: {result.stderr}'
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f'Failed to parse parquet data: {result.stdout}')


ORIGINAL_CSV = open(CSV_PATH, 'rb').read()
ORIGINAL_JSON = open(JSON_PATH, 'rb').read()
ORIGINAL_EXPECTED = expected_from_inputs()


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    run_pipeline()
    yield


def test_script_exists_and_is_file():
    assert os.path.isfile(SCRIPT_PATH), f'The required script {SCRIPT_PATH} does not exist.'


def test_pipeline_output_matches_input_records():
    assert get_parquet_data() == ORIGINAL_EXPECTED


def test_pipeline_ingests_changed_inputs():
    probe_csv = """timestamp,Temp_A,Pressure_X
2024-02-03 01:02:03,1.25,9.0
2024-02-03 01:03:03,2.5,10.75
"""
    probe_json = [
        {'time': '2024-02-03T01:02:03Z', 'sensor': 'TEMP_A', 'reading': 1.25},
        {'time': '2024-02-03 03:04:05+02:00', 'sensor': 'Flow_Y', 'reading': 7.125},
        {'time': '2024-02-03T01:05:06Z', 'sensor': 'PRESSURE_X', 'reading': 11.0},
    ]
    try:
        with open(CSV_PATH, 'w', encoding='utf-8', newline='') as f:
            f.write(probe_csv)
        with open(JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(probe_json, f)
        probe_expected = expected_from_inputs()
        run_pipeline()
        assert get_parquet_data() == probe_expected
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(ORIGINAL_CSV)
        with open(JSON_PATH, 'wb') as f:
            f.write(ORIGINAL_JSON)
        run_pipeline()


def test_parquet_file_exists():
    assert os.path.isfile(PARQUET_PATH), f'The finalized file {PARQUET_PATH} does not exist.'


def test_parquet_schema_and_row_count():
    data = get_parquet_data()

    # We expect 6 rows from factory 1 and 4 rows from factory 2.
    # 2 rows in factory 2 are exact duplicates of factory 1 data.
    # Total unique rows = 8.
    assert len(data) == 8, f'Expected exactly 8 deduplicated rows, but got {len(data)}.'

    expected_columns = {'timestamp', 'sensor_id', 'value', 'record_hash'}
    for idx, row in enumerate(data):
        assert set(row.keys()) == expected_columns, f'Row {idx} columns {set(row.keys())} do not match expected {expected_columns}.'


def test_parquet_data_normalization_and_hash():
    data = get_parquet_data()

    for idx, row in enumerate(data):
        ts = row['timestamp']
        sensor = row['sensor_id']
        val = row['value']
        rec_hash = row['record_hash']

        # Check ISO 8601 strict format with Z
        assert ts.endswith('Z') and '+' not in ts, f"Row {idx}: Timestamp '{ts}' is not in strict ISO 8601 format ending with 'Z'."
        assert len(ts) == 20 and ts[10] == 'T', f"Row {idx}: Timestamp '{ts}' is not formatted as YYYY-MM-DDTHH:MM:SSZ."

        # Check lowercase sensor_id
        assert sensor.islower(), f"Row {idx}: Sensor ID '{sensor}' is not entirely lowercase."

        # Check value is float
        assert isinstance(val, float), f'Row {idx}: Value {val} is not a float.'

        # Verify MD5 Hash logic
        expected_str = f'{ts}_{sensor}_{val:.2f}'
        expected_hash = hashlib.md5(expected_str.encode('utf-8')).hexdigest()
        assert rec_hash == expected_hash, f"Row {idx}: Hash mismatch for '{expected_str}'. Expected {expected_hash}, got {rec_hash}."


def test_parquet_sorting():
    data = get_parquet_data()

    for i in range(1, len(data)):
        prev = data[i - 1]
        curr = data[i]
        if prev['timestamp'] == curr['timestamp']:
            assert prev['sensor_id'] <= curr['sensor_id'], f"Data is not sorted by sensor_id for identical timestamp {prev['timestamp']}."
        else:
            assert prev['timestamp'] < curr['timestamp'], 'Data is not sorted by timestamp in ascending order.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
