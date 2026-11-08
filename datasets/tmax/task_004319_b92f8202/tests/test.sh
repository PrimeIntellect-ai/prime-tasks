#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

REPORT_JSON_PATH = "/home/user/report.json"
TOP_DESTINATIONS_CSV_PATH = "/home/user/top_destinations.csv"

def test_report_json_exists_and_correct():
    assert os.path.isfile(REPORT_JSON_PATH), f"File {REPORT_JSON_PATH} does not exist."

    with open(REPORT_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_JSON_PATH} is not valid JSON.")

    assert "path" in data, "The 'path' key is missing in report.json."
    assert "total_weight" in data, "The 'total_weight' key is missing in report.json."

    expected_path = ["Alpha", "Delta", "Echo", "Kilo"]
    expected_weight = 9

    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
    assert data["total_weight"] == expected_weight, f"Expected total_weight {expected_weight}, but got {data['total_weight']}."

def test_top_destinations_csv_exists_and_correct():
    assert os.path.isfile(TOP_DESTINATIONS_CSV_PATH), f"File {TOP_DESTINATIONS_CSV_PATH} does not exist."

    with open(TOP_DESTINATIONS_CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {TOP_DESTINATIONS_CSV_PATH} is empty.")

        assert header == ["node_name", "distance"], f"Expected header ['node_name', 'distance'], but got {header}."

        rows = list(reader)

    expected_rows = [
        ["Foxtrot", "1"],
        ["Delta", "3"],
        ["Charlie", "4"],
        ["Echo", "5"],
        ["Kilo", "9"]
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
