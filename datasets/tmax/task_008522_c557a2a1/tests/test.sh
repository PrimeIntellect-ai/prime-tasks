#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import pytest
from collections import defaultdict
from datetime import datetime

def test_output_directory_exists():
    assert os.path.isdir("/home/user/output"), "The directory /home/user/output was not created."

def test_error_log_contents():
    error_log_path = "/home/user/output/error.log"
    assert os.path.isfile(error_log_path), f"The file {error_log_path} does not exist."

    jsonl_path = "/home/user/data/events_2.jsonl"
    expected_errors = []
    if os.path.exists(jsonl_path):
        with open(jsonl_path, 'r') as f:
            for i, line in enumerate(f, 1):
                try:
                    json.loads(line)
                except json.JSONDecodeError:
                    expected_errors.append(f"ERROR:events_2.jsonl:{i}")

    with open(error_log_path, 'r') as f:
        actual_errors = [line.strip() for line in f if line.strip()]

    assert actual_errors == expected_errors, (
        f"Contents of {error_log_path} do not match expected error logs. "
        f"Expected: {expected_errors}, Got: {actual_errors}"
    )

def test_hourly_summary_contents():
    summary_path = "/home/user/output/hourly_summary.csv"
    assert os.path.isfile(summary_path), f"The file {summary_path} does not exist."

    # Compute expected summary from inputs
    counts = defaultdict(int)

    csv_path = "/home/user/data/events_1.csv"
    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ts = row['timestamp']
                action = row['action']
                dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
                hour_bucket = dt.strftime("%Y-%m-%d %H:00:00")
                counts[(hour_bucket, action)] += 1

    jsonl_path = "/home/user/data/events_2.jsonl"
    if os.path.exists(jsonl_path):
        with open(jsonl_path, 'r') as f:
            for line in f:
                try:
                    data = json.loads(line)
                    ts = data['timestamp']
                    action = data['action']
                    dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
                    hour_bucket = dt.strftime("%Y-%m-%d %H:00:00")
                    counts[(hour_bucket, action)] += 1
                except json.JSONDecodeError:
                    pass

    expected_rows = sorted([
        {'hour_bucket': k[0], 'action': k[1], 'count': str(v)}
        for k, v in counts.items()
    ], key=lambda x: (x['hour_bucket'], x['action']))

    with open(summary_path, 'r') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ['hour_bucket', 'action', 'count'], (
        f"CSV headers are incorrect. Expected ['hour_bucket', 'action', 'count'], got {reader.fieldnames}"
    )

    assert actual_rows == expected_rows, (
        f"Contents of {summary_path} do not match expected aggregated results. "
        f"Expected: {expected_rows}, Got: {actual_rows}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
