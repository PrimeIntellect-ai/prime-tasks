#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_rolling_config_stats_exists():
    """Test that the output CSV file exists."""
    file_path = "/home/user/rolling_config_stats.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The script did not create the expected output file."

def test_rolling_config_stats_content():
    """Test that the output CSV file has the correct headers and computed values."""
    file_path = "/home/user/rolling_config_stats.csv"

    if not os.path.isfile(file_path):
        pytest.fail(f"File {file_path} is missing.")

    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    expected_headers = ["timestamp", "max_memory", "rolling_avg"]
    assert rows[0] == expected_headers, f"Headers are incorrect. Expected {expected_headers}, got {rows[0]}."

    expected_data = [
        ["2024-01-01T00:00:00", "1000.00", "1000.00"],
        ["2024-01-01T02:00:00", "1100.00", "1050.00"],
        ["2024-01-01T03:00:00", "1200.00", "1100.00"],
        ["2024-01-01T04:00:00", "1250.00", "1183.33"],
        ["2024-01-01T05:00:00", "1325.00", "1258.33"],
        ["2024-01-01T06:00:00", "1400.00", "1325.00"]
    ]

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but found {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
