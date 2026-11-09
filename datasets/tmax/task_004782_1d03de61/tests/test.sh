#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_go_source_file_exists():
    path = "/home/user/process_sensors.go"
    assert os.path.isfile(path), f"The Go source file {path} was not found."

def test_cleaned_sensor_data_exists():
    path = "/home/user/cleaned_sensor_data.csv"
    assert os.path.isfile(path), f"The output file {path} was not found."

def test_cleaned_sensor_data_content():
    path = "/home/user/cleaned_sensor_data.csv"
    assert os.path.isfile(path), f"The output file {path} was not found."

    expected_rows = [
        ["timestamp", "sensor_id", "reading", "notes"],
        ["2023-10-01T10:00:00Z", "ALPHA-1", "10.50", "Start of run with newlines"],
        ["2023-10-01T10:00:30Z", "BETA-2", "5.00", "beta notes"],
        ["2023-10-01T10:01:00Z", "ALPHA-1", "11.50", "missing reading"],
        ["2023-10-01T10:01:30Z", "BETA-2", "5.00", "another missing"],
        ["2023-10-01T10:02:00Z", "ALPHA-1", "12.50", "normal"],
        ["2023-10-01T10:03:00Z", "GAMMA-3", "0.00", "totally empty"]
    ]

    actual_rows = []
    with open(path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected: {expected}, Actual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
