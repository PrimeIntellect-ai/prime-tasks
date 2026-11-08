#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def compute_expected_output(raw_file_path):
    if not os.path.exists(raw_file_path):
        return []

    # Read and filter valid rows
    valid_data = []
    with open(raw_file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('|')
            if len(parts) != 3:
                continue
            sensor_id, ts_str, temp_str = parts
            ts = int(ts_str)
            temp = float(temp_str)

            if -20.0 <= temp <= 60.0:
                valid_data.append((sensor_id, ts, temp))

    # Group by sensor_id
    grouped = {}
    for sensor_id, ts, temp in valid_data:
        if sensor_id not in grouped:
            grouped[sensor_id] = {}
        grouped[sensor_id][ts] = temp

    expected_rows = []
    for sensor_id in sorted(grouped.keys()):
        sensor_data = grouped[sensor_id]
        min_ts = min(sensor_data.keys())
        max_ts = max(sensor_data.keys())

        last_temp = None
        for current_ts in range(min_ts, max_ts + 1, 60):
            if current_ts in sensor_data:
                last_temp = sensor_data[current_ts]

            # Append formatted row
            expected_rows.append(f"{sensor_id},{current_ts},{last_temp}")

    return expected_rows

def test_processed_telemetry_file_exists():
    """Ensure the target output file exists."""
    file_path = "/home/user/processed_telemetry.csv"
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

def test_processed_telemetry_content():
    """Verify that the processed telemetry data is correct based on the raw data."""
    raw_path = "/home/user/raw_telemetry.txt"
    processed_path = "/home/user/processed_telemetry.csv"

    assert os.path.exists(raw_path), f"Input file {raw_path} is missing."
    assert os.path.exists(processed_path), f"Output file {processed_path} is missing."

    expected_lines = compute_expected_output(raw_path)

    with open(processed_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Row count mismatch. Expected {len(expected_lines)} rows, got {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at row {i+1}.\nExpected: {expected}\nActual:   {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
