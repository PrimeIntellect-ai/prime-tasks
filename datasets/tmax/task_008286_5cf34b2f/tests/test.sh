#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_rolling_memory_output():
    output_path = "/home/user/rolling_memory.csv"

    assert os.path.exists(output_path), f"Output file {output_path} was not created."

    expected_data = [
        ("2023-10-01T10:00:00Z", 1536.0),
        ("2023-10-01T10:01:00Z", 1536.0),
        ("2023-10-01T10:02:00Z", 2218.67),
        ("2023-10-01T10:03:00Z", 3328.0),
        ("2023-10-01T10:04:00Z", 3993.6),
        ("2023-10-01T10:05:00Z", 5017.6),
        ("2023-10-01T10:06:00Z", 6041.6),
        ("2023-10-01T10:07:00Z", 6451.2),
        ("2023-10-01T10:08:00Z", 6246.4),
        ("2023-10-01T10:09:00Z", 6041.6),
        ("2023-10-01T10:10:00Z", 5836.8),
    ]

    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"File {output_path} is empty.")

        assert headers == ["timestamp_minute", "rolling_avg_memory"], \
            f"Headers in {output_path} are incorrect. Expected ['timestamp_minute', 'rolling_avg_memory'], got {headers}"

        rows = list(reader)

    assert len(rows) == len(expected_data), \
        f"Expected {len(expected_data)} rows of data, but found {len(rows)}."

    for i, (row, expected) in enumerate(zip(rows, expected_data)):
        assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns: {row}"

        timestamp, value_str = row
        expected_ts, expected_val = expected

        assert timestamp == expected_ts, f"Row {i+1} timestamp mismatch. Expected {expected_ts}, got {timestamp}"

        try:
            value = float(value_str)
        except ValueError:
            pytest.fail(f"Row {i+1} value '{value_str}' cannot be parsed as a float.")

        # Allow small floating point differences due to rounding
        assert abs(value - expected_val) < 0.015, \
            f"Row {i+1} rolling average mismatch. Expected ~{expected_val}, got {value}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
