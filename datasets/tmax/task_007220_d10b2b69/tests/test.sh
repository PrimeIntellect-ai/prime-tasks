#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_merged_analysis_exists():
    path = "/home/user/merged_analysis.csv"
    assert os.path.exists(path), f"Output file {path} does not exist."
    assert os.path.isfile(path), f"Output path {path} is not a file."

def test_merged_analysis_format_and_content():
    path = "/home/user/merged_analysis.csv"
    assert os.path.exists(path), f"Output file {path} does not exist."

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The merged_analysis.csv file is empty."

    headers = rows[0]
    expected_headers = ["timestamp", "cpu_usage", "avg_latency"]
    assert headers == expected_headers, f"Headers mismatch. Expected {expected_headers}, got {headers}."

    data_rows = rows[1:]

    # Expected data based on the truth setup
    expected_data = [
        ("2023-10-01 10:00:00", 40.0, 150.0),
        ("2023-10-01 10:01:00", 45.0, 500.0),
        ("2023-10-01 10:02:00", 50.0, 50.0),
        ("2023-10-01 10:03:00", 60.0, None),
        ("2023-10-01 10:04:00", 70.0, None),
        ("2023-10-01 10:05:00", 80.0, 500.0),
    ]

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} rows of data, got {len(data_rows)}."

    for i, (row, expected) in enumerate(zip(data_rows, expected_data)):
        assert len(row) == 3, f"Row {i+1} does not have exactly 3 columns: {row}"

        ts, cpu, lat = row
        exp_ts, exp_cpu, exp_lat = expected

        assert ts == exp_ts, f"Row {i+1} timestamp mismatch. Expected '{exp_ts}', got '{ts}'."

        try:
            cpu_val = float(cpu)
        except ValueError:
            pytest.fail(f"Row {i+1} cpu_usage is not a valid float: '{cpu}'")

        assert abs(cpu_val - exp_cpu) < 0.01, f"Row {i+1} cpu_usage mismatch. Expected {exp_cpu}, got {cpu_val}."
        assert "." in cpu and len(cpu.split(".")[1]) >= 1, f"Row {i+1} cpu_usage should be formatted with 1 decimal place. Got '{cpu}'."

        if exp_lat is None:
            assert lat == "", f"Row {i+1} avg_latency should be completely empty, got '{lat}'."
        else:
            try:
                lat_val = float(lat)
            except ValueError:
                pytest.fail(f"Row {i+1} avg_latency is not a valid float: '{lat}'")

            assert abs(lat_val - exp_lat) < 0.01, f"Row {i+1} avg_latency mismatch. Expected {exp_lat}, got {lat_val}."
            assert "." in lat and len(lat.split(".")[1]) >= 1, f"Row {i+1} avg_latency should be formatted with 1 decimal place. Got '{lat}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
