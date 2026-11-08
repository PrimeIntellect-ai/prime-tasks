#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import csv
import pytest
from datetime import datetime, timedelta

def test_raw_log_copied():
    raw_log_path = "/home/user/workspace/raw.log"
    assert os.path.isfile(raw_log_path), f"Expected file {raw_log_path} does not exist."

    # Check if it matches the original file
    original_log_path = "/var/tmp/etl_drop/server_metrics.log"
    if os.path.isfile(original_log_path):
        with open(original_log_path, 'r') as f1, open(raw_log_path, 'r') as f2:
            assert f1.read() == f2.read(), f"Content of {raw_log_path} does not match {original_log_path}."

def test_etl_output_exists():
    output_path = "/home/user/workspace/etl_output.csv"
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist."

def test_etl_output_content():
    raw_log_path = "/var/tmp/etl_drop/server_metrics.log"
    assert os.path.isfile(raw_log_path), f"Original log file {raw_log_path} is missing."

    # Step 1: Read and deduplicate
    with open(raw_log_path, 'r') as f:
        lines = f.readlines()

    unique_lines = list(dict.fromkeys(line.strip() for line in lines if line.strip()))

    # Step 2: Parse lines
    # Format: [2023-10-14 10:01:45] INFO [MetricAgent] CPU_USAGE=47.1% Memory=1030MB
    pattern = re.compile(r"\[(.*?)\] .*? CPU_USAGE=([\d\.]+)%")

    minute_data = {}
    for line in unique_lines:
        match = pattern.search(line)
        if match:
            timestamp_str = match.group(1)
            cpu_val = float(match.group(2))

            # Extract minute-level timestamp
            dt = datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
            minute_key = dt.strftime("%Y-%m-%d %H:%M")

            if minute_key not in minute_data:
                minute_data[minute_key] = []
            minute_data[minute_key].append(cpu_val)

    # Step 3: Calculate average per minute
    minute_avg = {k: sum(v)/len(v) for k, v in minute_data.items()}

    # Step 4: Resampling and Gap-Filling (10:00 to 10:10)
    start_dt = datetime.strptime("2023-10-14 10:00", "%Y-%m-%d %H:%M")

    filled_data = []
    last_val = None

    for i in range(11):
        current_dt = start_dt + timedelta(minutes=i)
        current_str = current_dt.strftime("%Y-%m-%d %H:%M")

        if current_str in minute_avg:
            val = minute_avg[current_str]
            last_val = val
        else:
            val = last_val

        filled_data.append((current_str, val))

    # Step 5: Rolling Statistics and formatting
    expected_rows = [["Timestamp", "Avg_CPU", "Rolling_Avg_CPU"]]

    for i in range(len(filled_data)):
        current_str, current_val = filled_data[i]

        # Get up to 3 minutes window
        window_start = max(0, i - 2)
        window_vals = [filled_data[j][1] for j in range(window_start, i + 1)]
        rolling_avg = sum(window_vals) / len(window_vals)

        expected_rows.append([
            current_str,
            f"{current_val:.1f}",
            f"{rolling_avg:.1f}"
        ])

    # Read actual CSV
    output_path = "/home/user/workspace/etl_output.csv"
    actual_rows = []
    with open(output_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_rows.append(row)

    # Compare
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
