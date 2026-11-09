#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_processed_sensors_file_exists():
    path = "/home/user/workspace/processed_sensors.csv"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

def test_processed_sensors_content():
    path = "/home/user/workspace/processed_sensors.csv"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    expected_rows = [
        ["timestamp", "sensor_name", "value", "remarks"],
        ["2023-10-01T10:00:00", "sensor_alpha", "10.5", "Routine check"],
        ["2023-10-01T10:00:00", "sensor_beta", "20.1", "Routine check"],
        ["2023-10-01T10:00:00", "sensor_gamma", "30.2", "Routine check"],
        ["2023-10-01T10:05:00", "sensor_alpha", "10.6", "Notice: Intermittent signal on beta"],
        ["2023-10-01T10:05:00", "sensor_gamma", "30.5", "Notice: Intermittent signal on beta"],
        ["2023-10-01T10:10:00", "sensor_alpha", "10.8", "All clear"],
        ["2023-10-01T10:10:00", "sensor_beta", "20.5", "All clear"],
        ["2023-10-01T10:10:00", "sensor_gamma", "30.8", "All clear"],
        ["2023-10-01T10:15:00", "sensor_alpha", "11.0", "Gamma offline restarting"],
        ["2023-10-01T10:15:00", "sensor_beta", "20.7", "Gamma offline restarting"]
    ]

    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "The processed CSV file is empty."
    assert actual_rows[0] == expected_rows[0], f"Header mismatch. Expected {expected_rows[0]}, got {actual_rows[0]}"

    # Check lengths
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), got {len(actual_rows)}."

    # Check each row exactly
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch.\nExpected: {expected}\nActual: {actual}"

def test_extracted_raw_file_exists():
    path = "/home/user/workspace/raw_sensors.csv"
    # The task says "Copy sensor_dump.tar.gz to your working directory... and extract it."
    # We check if the extracted file exists to ensure step 1 was followed.
    assert os.path.isfile(path), f"Extracted file {path} does not exist in the workspace."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
