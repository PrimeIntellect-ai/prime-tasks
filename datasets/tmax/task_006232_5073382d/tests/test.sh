#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest
from datetime import datetime, timezone
from collections import defaultdict

OUTPUT_FILE = '/home/user/top_failure_windows.csv'
WEB_LOG = '/home/user/logs/web_server.log'
API_LOG = '/home/user/logs/api_gateway.jsonl'
DB_LOG = '/home/user/logs/db_query.log'

def get_expected_top_10():
    windows = defaultdict(int)

    # Parse web server log
    if os.path.exists(WEB_LOG):
        with open(WEB_LOG, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row['status_code']) >= 500:
                    ts_str = row['timestamp'].replace('Z', '+00:00')
                    dt = datetime.fromisoformat(ts_str)
                    ts = int(dt.timestamp())
                    windows[(ts // 60) * 60] += 1

    # Parse API gateway log
    if os.path.exists(API_LOG):
        with open(API_LOG, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                data = json.loads(line)
                if data.get('error') is True:
                    ts = data['ts'] // 1000
                    windows[(ts // 60) * 60] += 1

    # Parse DB query log
    if os.path.exists(DB_LOG):
        with open(DB_LOG, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(']', 1)
                if len(parts) == 2:
                    ts_str = parts[0][1:] # Remove leading '['
                    if 'status=ERROR' in parts[1]:
                        dt = datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S').replace(tzinfo=timezone.utc)
                        ts = int(dt.timestamp())
                        windows[(ts // 60) * 60] += 1

    # Sort by failures (descending), then timestamp (ascending)
    sorted_windows = sorted(windows.items(), key=lambda x: (-x[1], x[0]))
    return sorted_windows[:10]

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

def test_top_failure_windows_correct():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

    expected_top_10 = get_expected_top_10()
    actual_top_10 = []

    with open(OUTPUT_FILE, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['window_start_epoch', 'total_failures'], \
            f"CSV header is incorrect. Expected ['window_start_epoch', 'total_failures'], got {header}"

        for row in reader:
            if not row:
                continue
            try:
                actual_top_10.append((int(row[0]), int(row[1])))
            except ValueError:
                pytest.fail(f"Invalid data in CSV row: {row}. Values must be integers.")

    assert len(actual_top_10) == len(expected_top_10), \
        f"Expected exactly {len(expected_top_10)} rows in the output, got {len(actual_top_10)}."

    for i, (expected, actual) in enumerate(zip(expected_top_10, actual_top_10)):
        assert expected == actual, \
            f"Mismatch at rank {i+1}. Expected window {expected[0]} with {expected[1]} failures, " \
            f"but got window {actual[0]} with {actual[1]} failures."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
