#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_anomalies_csv_exists():
    output_file = "/home/user/anomalies.csv"
    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist."

def test_anomalies_csv_content():
    output_file = "/home/user/anomalies.csv"
    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist."

    with open(output_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"File {output_file} is empty."

    header = rows[0]
    expected_header = ["hour", "count", "rolling_avg"]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}"

    # The first active bucket is anomalous because its preceding rolling average
    # is 0.0. Hour 12 is also anomalous with count 30 and rolling average 10.0.
    expected_rows = [
        ["2023-10-01T00", "10", "0.0"],
        ["2023-10-01T12", "30", "10.0"],
    ]

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(data_rows)}"

    for expected, actual in zip(expected_rows, data_rows):
        assert actual == expected, f"Expected row {expected}, but got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
