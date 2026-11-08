#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_rolling_stats_csv_exists():
    file_path = "/home/user/rolling_stats.csv"
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

def test_rolling_stats_csv_content():
    file_path = "/home/user/rolling_stats.csv"

    expected_rows = [
        ["utc_time", "lang", "msg", "val", "rolling_avg"],
        ["2023-10-25T10:00:00Z", "zh", "系统 失敗", "10.0", "10.00"],
        ["2023-10-25T10:02:00Z", "ja", "システム 失敗", "15.0", "12.50"],
        ["2023-10-25T10:05:00Z", "ja", "失敗", "20.0", "15.00"],
        ["2023-10-25T10:10:00Z", "zh", "验证 失敗", "30.0", "21.67"],
        ["2023-10-25T10:20:00Z", "ja", "接続 失敗", "40.0", "30.00"]
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "The CSV file is empty."

    # Check headers
    assert actual_rows[0] == expected_rows[0], f"Expected headers {expected_rows[0]}, but got {actual_rows[0]}."

    # Check number of rows
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}."

    # Check content row by row
    for i, (actual, expected) in enumerate(zip(actual_rows[1:], expected_rows[1:]), start=1):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
