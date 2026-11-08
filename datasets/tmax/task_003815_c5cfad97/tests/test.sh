#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import pytest

def test_drift_report_exists_and_correct():
    report_path = "/home/user/drift_report.csv"

    assert os.path.isfile(report_path), f"Expected output file {report_path} does not exist."

    with open(report_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"The file {report_path} is empty.")

        expected_headers = ["server_id", "utc_timestamp", "jaccard_distance"]
        assert headers == expected_headers, f"Expected headers {expected_headers}, but got {headers}."

        rows = list(reader)

    expected_rows = [
        ["app-01", "1696161600", "0.40"],
        ["app-01", "1696165200", "0.00"],
        ["app-02", "1696165200", "0.50"],
        ["app-02", "1696168800", "1.00"],
        ["db-01", "1696176000", "0.83"],
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(rows)}."

    for i, (actual_row, expected_row) in enumerate(zip(rows, expected_rows)):
        assert len(actual_row) == 3, f"Row {i+1} does not have exactly 3 columns: {actual_row}"

        # Check server_id
        assert actual_row[0] == expected_row[0], f"Row {i+1}: expected server_id '{expected_row[0]}', got '{actual_row[0]}'."

        # Check utc_timestamp
        assert actual_row[1] == expected_row[1], f"Row {i+1}: expected utc_timestamp '{expected_row[1]}', got '{actual_row[1]}'."

        # Check jaccard_distance (allow float comparison in case formatting differs slightly like 0.4 vs 0.40)
        try:
            actual_dist = float(actual_row[2])
            expected_dist = float(expected_row[2])
        except ValueError:
            pytest.fail(f"Row {i+1}: jaccard_distance must be a number, got '{actual_row[2]}'.")

        assert abs(actual_dist - expected_dist) < 1e-5, f"Row {i+1}: expected jaccard_distance {expected_dist:.2f}, got {actual_dist:.2f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
