#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import sys
from datetime import timedelta

import pandas as pd
import pytest
from pandas.api.types import is_datetime64_any_dtype, is_integer_dtype, is_numeric_dtype

SCRIPT_PATH = '/home/user/process_configs.py'
OUTPUT_PATH = '/home/user/output/tracked_changes.parquet'
CSV_PATH = '/home/user/data/legacy_configs.csv'
JSON_PATH = '/home/user/data/modern_configs.json'

CANONICAL_CSV = [
    {
        'timestamp': '2023-10-01T10:00:00Z',
        'server_name': 'SRV-01',
        'raw_diff': 'System rebooted\n[UPDATE] max_connections=100\n[ADD] timeout=30\nDone.',
    },
    {
        'timestamp': '2023-10-01T11:30:00Z',
        'server_name': 'srv_02',
        'raw_diff': '[UPDATE] cache_size=1024',
    },
    {
        'timestamp': '2023-10-01T12:00:00Z',
        'server_name': 'SRV-01',
        'raw_diff': 'Warning: load high\n[UPDATE] workers=8\nResolving...',
    },
    {
        'timestamp': '2023-10-01T14:30:00Z',
        'server_name': 'SRV_01',
        'raw_diff': 'Routine\n[ADD] backup_path=/tmp\n',
    },
]

CANONICAL_JSON = [
    {'time': '2023-10-01T10:15:00Z', 'host_id': 'srv-02', 'changed_keys': ['ssl_cert']},
    {'time': '2023-10-01T13:45:00Z', 'host_id': 'SRV-01', 'changed_keys': ['db_host', 'db_port']},
]


def normalize_server(value):
    return value.lower().replace('-', '_')


def build_expected_from_inputs():
    csv_df = pd.read_csv(CSV_PATH)
    csv_records = csv_df.to_dict(orient='records')
    assert csv_records == CANONICAL_CSV, 'The legacy input data was modified or parsed incorrectly.'

    with open(JSON_PATH, encoding='utf-8') as handle:
        json_records = json.load(handle)
    assert json_records == CANONICAL_JSON, 'The modern input data was modified.'

    events = []
    key_pattern = re.compile(r'\[(?:UPDATE|ADD)\]\s+([A-Za-z_][A-Za-z0-9_]*)\s*=')

    for row in csv_records:
        keys = key_pattern.findall(row['raw_diff'])
        events.append({
            'timestamp': pd.to_datetime(row['timestamp'], utc=True),
            'server': normalize_server(row['server_name']),
            'change_count': len(keys),
        })

    for row in json_records:
        events.append({
            'timestamp': pd.to_datetime(row['time'], utc=True),
            'server': normalize_server(row['host_id']),
            'change_count': len(row['changed_keys']),
        })

    events.sort(key=lambda event: event['timestamp'])
    for event in events:
        left_edge = event['timestamp'] - timedelta(hours=3)
        event['rolling_3h_changes'] = float(sum(
            candidate['change_count']
            for candidate in events
            if candidate['server'] == event['server']
            and left_edge < candidate['timestamp'] <= event['timestamp']
        ))
    return events


EXPECTED_EVENTS = build_expected_from_inputs()


@pytest.fixture(scope='session', autouse=True)
def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f'Required script {SCRIPT_PATH} does not exist or is not a regular file.'

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    proc = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, (
        f'{SCRIPT_PATH} failed with exit code {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert os.path.isfile(SCRIPT_PATH), f'Required script {SCRIPT_PATH} was removed during execution.'


def load_output():
    df = pd.read_parquet(OUTPUT_PATH)
    if 'timestamp' not in df.columns:
        assert df.index.name == 'timestamp', 'timestamp must be a column or the named index.'
        df = df.reset_index()
    return df


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f'The output file {OUTPUT_PATH} does not exist.'
    assert os.path.getsize(OUTPUT_PATH) > 0, f'The output file {OUTPUT_PATH} is empty.'


def test_parquet_data_correctness():
    df = load_output()

    required = {'timestamp', 'server', 'change_count', 'rolling_3h_changes'}
    assert required.issubset(df.columns), f'Missing required columns: {sorted(required - set(df.columns))}'
    assert len(df) == len(EXPECTED_EVENTS), f'Expected {len(EXPECTED_EVENTS)} events, got {len(df)}.'

    assert is_datetime64_any_dtype(df['timestamp'].dtype), 'timestamp must be stored as a pandas datetime type.'
    assert df['timestamp'].dt.tz is not None, 'timestamp values must be timezone-aware UTC datetimes.'
    assert all(value.utcoffset() == timedelta(0) for value in df['timestamp']), 'All timestamps must be UTC.'
    assert is_integer_dtype(df['change_count'].dtype), 'change_count must have an integer dtype.'
    assert is_numeric_dtype(df['rolling_3h_changes'].dtype), 'rolling_3h_changes must be numeric.'
    assert not df[list(required)].isnull().any().any(), 'Required output fields must not contain null values.'
    assert df['timestamp'].is_monotonic_increasing, 'Events must be sorted chronologically.'

    actual_servers = list(df['server'].unique())
    assert set(actual_servers) == {'srv_01', 'srv_02'}, (
        f'Server names were not normalized correctly. Found: {actual_servers}'
    )

    srv01_counts = int(df[df['server'] == 'srv_01']['change_count'].sum())
    srv02_counts = int(df[df['server'] == 'srv_02']['change_count'].sum())
    assert srv01_counts == 6, f'Expected 6 total changes for srv_01, got {srv01_counts}'
    assert srv02_counts == 2, f'Expected 2 total changes for srv_02, got {srv02_counts}'

    srv01_rolling = df[df['server'] == 'srv_01'].sort_values('timestamp')['rolling_3h_changes'].tolist()
    expected_srv01_rolling = [2.0, 3.0, 3.0, 4.0]
    assert srv01_rolling == expected_srv01_rolling, (
        f'Rolling 3h changes for srv_01 are incorrect. '
        f'Expected {expected_srv01_rolling}, got {srv01_rolling}'
    )

    actual_rows = df[['timestamp', 'server', 'change_count', 'rolling_3h_changes']].to_dict(orient='records')
    for position, (actual, expected) in enumerate(zip(actual_rows, EXPECTED_EVENTS)):
        assert actual['timestamp'] == expected['timestamp'], (
            f'Incorrect timestamp at row {position}: expected {expected["timestamp"]}, got {actual["timestamp"]}'
        )
        assert actual['server'] == expected['server'], (
            f'Incorrect server at row {position}: expected {expected["server"]}, got {actual["server"]}'
        )
        assert actual['change_count'] == expected['change_count'], (
            f'Incorrect change_count at row {position}: expected {expected["change_count"]}, '
            f'got {actual["change_count"]}'
        )
        assert actual['rolling_3h_changes'] == pytest.approx(expected['rolling_3h_changes']), (
            f'Incorrect rolling_3h_changes at row {position}: '
            f'expected {expected["rolling_3h_changes"]}, got {actual["rolling_3h_changes"]}'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
