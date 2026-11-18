#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict

import pytest

HOME = '/home/user'
RAW_DATA = os.path.join(HOME, 'raw_data')
PIPELINE = os.path.join(HOME, 'run_pipeline.sh')
AGGREGATE = os.path.join(HOME, 'aggregate.py')
OUTPUT = os.path.join(HOME, 'hourly_averages.csv')
VALID_LINE_RE = re.compile(r'^(\d{4}-\d{2}-\d{2} \d{2}):\d{2}:\d{2},([a-zA-Z0-9]+),temp,(\d+(?:\.\d+)?)$')


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [PIPELINE],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'run_pipeline.sh failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(OUTPUT), 'Pipeline did not create /home/user/hourly_averages.csv.'


def expected_rows_from_raw_data():
    sums = defaultdict(float)
    counts = defaultdict(int)

    for filename in os.listdir(RAW_DATA):
        if not filename.endswith('.csv'):
            continue
        filepath = os.path.join(RAW_DATA, filename)
        with open(filepath, 'r') as f:
            for line in f:
                match = VALID_LINE_RE.match(line.strip())
                if match:
                    hour_str = match.group(1) + ':00:00'
                    sensor_id = match.group(2)
                    temp = float(match.group(3))
                    key = (hour_str, sensor_id)
                    sums[key] += temp
                    counts[key] += 1

    rows = []
    for key in sums:
        rows.append((key[0], key[1], f'{sums[key] / counts[key]:.2f}'))
    rows.sort(key=lambda row: (row[0], row[1]))
    return rows


def assert_output_matches_raw_data():
    expected_rows = expected_rows_from_raw_data()
    actual_rows = []
    with open(OUTPUT, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['timestamp', 'sensor_id', 'avg_temp'], f'Incorrect header in output CSV: {header}'
        for row in reader:
            if row:
                actual_rows.append(tuple(row))

    assert len(actual_rows) == len(expected_rows), (
        f'Expected {len(expected_rows)} rows, but got {len(actual_rows)}.'
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f'Row {i + 1} mismatch: expected {expected}, got {actual}.'


@pytest.fixture(scope='session', autouse=True)
def execute_original_pipeline():
    assert os.path.isfile(PIPELINE), f'Expected script {PIPELINE} does not exist.'
    assert os.access(PIPELINE, os.X_OK), f'Script {PIPELINE} is not executable.'
    assert os.path.isfile(AGGREGATE), f'Expected Python script {AGGREGATE} does not exist.'
    assert os.path.isdir(RAW_DATA), f'Raw data directory {RAW_DATA} is missing.'
    run_pipeline()


def test_run_pipeline_script_exists_and_executable():
    assert os.path.isfile(PIPELINE), f'Expected script {PIPELINE} does not exist.'
    assert os.access(PIPELINE, os.X_OK), f'Script {PIPELINE} is not executable.'


def test_aggregate_script_exists():
    assert os.path.isfile(AGGREGATE), f'Expected Python script {AGGREGATE} does not exist.'


def test_hourly_averages_csv_exists():
    assert os.path.isfile(OUTPUT), f'Expected output file {OUTPUT} does not exist.'


def test_hourly_averages_content():
    assert os.path.isdir(RAW_DATA), f'Raw data directory {RAW_DATA} is missing.'
    assert_output_matches_raw_data()


def test_pipeline_on_fresh_data_and_invokes_aggregate():
    backup_dir = tempfile.mkdtemp(prefix='raw_data_backup_')
    aggregate_backup = os.path.join(HOME, '.aggregate.py.verifier-original-' + secrets.token_hex(8))
    marker = os.path.join('/tmp', 'aggregate_invoked_' + secrets.token_hex(8))

    try:
        for name in os.listdir(RAW_DATA):
            shutil.move(os.path.join(RAW_DATA, name), os.path.join(backup_dir, name))

        sensor_a = 'R' + secrets.token_hex(5)
        sensor_b = 'S' + secrets.token_hex(5)
        values = [secrets.randbelow(3000) / 100 + 5 for _ in range(6)]

        with open(os.path.join(RAW_DATA, 'fresh_a.csv'), 'w') as f:
            f.write('timestamp,sensor_id,metric,value\n')
            f.write(f'2026-07-04 03:02:01,{sensor_b},temp,{values[0]:.2f}\n')
            f.write('[ERROR] generated verifier junk\n')
            f.write(f'2026-07-04 03:58:59,{sensor_b},temp,{values[1]:.2f}\n')
            f.write(f'2026-07-04 03:15:00,{sensor_a},temp,{values[2]:.2f}\n')
            f.write(f'2026-07-04 03:16:00,{sensor_a},humidity,99.0\n')
            f.write(f' 2026-07-04 03:17:00,{sensor_a},temp,999.0\n')

        with open(os.path.join(RAW_DATA, 'fresh_b.csv'), 'w') as f:
            f.write(f'2026-07-04 04:00:00,{sensor_a},temp,{values[3]:.2f}\n')
            f.write(f'2026-07-04 04:30:30,{sensor_a},temp,{values[4]:.2f}\n')
            f.write('Header: timestamp,sensor,metric,val\n')
            f.write(f'2026-07-05 00:00:01,{sensor_b},temp,{values[5]:.2f}\n')
            f.write(f'2026-07-05 00:10:01,bad_sensor,temp,100.0\n')

        with open(os.path.join(RAW_DATA, 'must_be_ignored.txt'), 'w') as f:
            f.write(f'2026-07-04 03:00:00,{sensor_a},temp,9999.0\n')

        shutil.move(AGGREGATE, aggregate_backup)
        wrapper = f'''#!/usr/bin/env python3
import runpy
import sys
with open({marker!r}, 'w') as marker_file:
    marker_file.write('invoked')
sys.argv[0] = {aggregate_backup!r}
runpy.run_path({aggregate_backup!r}, run_name='__main__')
'''
        with open(AGGREGATE, 'w') as f:
            f.write(wrapper)
        os.chmod(AGGREGATE, 0o755)

        run_pipeline()
        assert os.path.isfile(marker), 'run_pipeline.sh did not invoke /home/user/aggregate.py.'
        assert_output_matches_raw_data()
    finally:
        if os.path.exists(AGGREGATE):
            os.remove(AGGREGATE)
        if os.path.exists(aggregate_backup):
            shutil.move(aggregate_backup, AGGREGATE)
        if os.path.exists(marker):
            os.remove(marker)
        for name in os.listdir(RAW_DATA):
            path = os.path.join(RAW_DATA, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
        for name in os.listdir(backup_dir):
            shutil.move(os.path.join(backup_dir, name), os.path.join(RAW_DATA, name))
        os.rmdir(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
