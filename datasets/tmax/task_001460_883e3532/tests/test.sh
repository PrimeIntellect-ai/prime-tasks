#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import stat
import subprocess
from collections import defaultdict

import pytest

SCRIPT = '/home/user/etl_pipeline.py'
RAW = '/home/user/raw_sensor_data.csv'
OUTPUT = '/home/user/processed_data.jsonl'


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'Pipeline exited with status {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} was not created.'


def read_jsonl(path):
    records = []
    with open(path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f'Line {line_num} in {path} is not valid JSON: {e}')
    return records


@pytest.fixture(scope='module', autouse=True)
def execute_submitted_pipeline():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} is missing.'
    mode = os.stat(SCRIPT, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f'Script {SCRIPT} must be a regular file.'
    assert os.path.getsize(SCRIPT) > 0, f'Script {SCRIPT} is empty.'
    run_pipeline()


def test_processed_data_exists():
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} was not created.'


def test_processed_data_contents():
    expected_records = [
        {'ts': '2023-10-01T07:00:00', 'id': 'S1', 'temp': 28.0, 'meta': 'Early bird'},
        {'ts': '2023-10-01T09:00:00', 'id': 'S1', 'temp': 21.0, 'meta': 'Restarted with error €'},
        {'ts': '2023-10-01T08:00:00', 'id': 'S2', 'temp': 24.1, 'meta': 'Initial startup'},
        {'ts': '2023-10-01T09:15:00', 'id': 'S2', 'temp': 20.5, 'meta': 'Back online all good'},
    ]

    actual_records = read_jsonl(OUTPUT)
    assert len(actual_records) == len(expected_records), (
        f'Expected {len(expected_records)} records, but found {len(actual_records)} in {OUTPUT}.'
    )

    def sort_key(r):
        return (r.get('id', ''), r.get('ts', ''))

    expected_sorted = sorted(expected_records, key=sort_key)
    actual_sorted = sorted(actual_records, key=sort_key)
    for i, (exp, act) in enumerate(zip(expected_sorted, actual_sorted)):
        assert act == exp, f'Record mismatch at sorted index {i}. Expected: {exp}, Actual: {act}'

    # The emitted records themselves must be in grouped, chronological order.
    assert actual_records == expected_records, (
        f'Output ordering is incorrect. Expected: {expected_records}, Actual: {actual_records}'
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} is missing.'


def derive_expected(path):
    groups = defaultdict(list)
    with open(path, 'r', encoding='cp1252', newline='') as f:
        for row in csv.DictReader(f):
            try:
                temp = float(row['temperature'])
            except (TypeError, ValueError):
                continue
            if temp <= 20.0:
                continue
            groups[row['sensor_id']].append({
                'ts': row['timestamp'],
                'id': row['sensor_id'],
                'temp': temp,
                'meta': row['metadata'].replace('\r\n', ' ').replace('\n', ' '),
            })

    expected = []
    for sensor_id in sorted(groups):
        expected.extend(sorted(groups[sensor_id], key=lambda r: r['ts'])[:2])
    return expected


def test_pipeline_processes_changed_multiline_input():
    original_raw = open(RAW, 'rb').read()
    original_output = open(OUTPUT, 'rb').read()
    rows = [
        ['2024-05-01T12:00:00', 'A7', '23.75', 'Later\nreading €'],
        ['2024-05-01T09:30:00', 'B2', '18.0', 'Below threshold'],
        ['2024-05-01T08:00:00', 'A7', '21.25', 'First\r\narrivée ñ'],
        ['2024-05-01T07:00:00', 'B2', '24.5', 'Cold start\nready'],
        ['2024-05-01T10:00:00', 'A7', 'not-a-number', 'Bad temperature'],
        ['2024-05-01T11:00:00', 'B2', '26.0', 'Second °C'],
        ['2024-05-01T13:00:00', 'A7', '30.0', 'Third qualifying row'],
        ['2024-05-01T06:00:00', 'A7', '19.5', 'Valid but filtered'],
        ['2024-05-01T14:00:00', 'B2', '27.0', 'Third for B'],
        ['2024-05-01T08:30:00', 'B2', '', 'Offline'],
    ]

    try:
        with open(RAW, 'w', encoding='cp1252', newline='') as f:
            writer = csv.writer(f, lineterminator='\r\n')
            writer.writerow(['timestamp', 'sensor_id', 'temperature', 'metadata'])
            writer.writerows(rows)

        expected = derive_expected(RAW)
        run_pipeline()

        with open(OUTPUT, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        assert all(line.strip() for line in lines), 'Output contains a blank, non-JSON line.'

        actual = read_jsonl(OUTPUT)
        assert actual == expected, (
            'Pipeline did not correctly parse, clean, filter, sample, or order the changed input. '
            f'Expected: {expected}, Actual: {actual}'
        )
        for record in actual:
            assert set(record) == {'ts', 'id', 'temp', 'meta'}
            assert isinstance(record['ts'], str)
            assert isinstance(record['id'], str)
            assert isinstance(record['temp'], float)
            assert isinstance(record['meta'], str)
    finally:
        with open(RAW, 'wb') as f:
            f.write(original_raw)
        with open(OUTPUT, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
