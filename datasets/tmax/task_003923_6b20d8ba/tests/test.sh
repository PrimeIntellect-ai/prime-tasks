#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

OUTPUT_DIR = "/home/user/organized_data"
DATABASE_CSV = os.path.join(OUTPUT_DIR, "database_logs.csv")
FRONTEND_JSON = os.path.join(OUTPUT_DIR, "frontend_logs.json")

def test_output_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} does not exist. The script should have created it."

def test_database_logs_csv():
    assert os.path.isfile(DATABASE_CSV), f"Expected CSV file {DATABASE_CSV} is missing."

    expected_rows = [
        {"timestamp": "2023-10-01 09:05:00", "level": "INFO", "message": "Service started"},
        {"timestamp": "2023-10-01 10:05:00", "level": "INFO", "message": "Connection established"},
        {"timestamp": "2023-10-01 10:05:30", "level": "ERROR", "message": 'Query syntax error "SELECT * FROM;"'},
        {"timestamp": "2023-10-01 10:06:00", "level": "ERROR", "message": "Timeout on query execution"}
    ]

    with open(DATABASE_CSV, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"{DATABASE_CSV} is empty.")

        # Check header
        assert header == ["timestamp", "level", "message"], f"CSV header is incorrect. Expected ['timestamp', 'level', 'message'], got {header}"

        # Read rows
        rows = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"Row has incorrect number of columns: {row}"
            rows.append({
                "timestamp": row[0],
                "level": row[1],
                "message": row[2]
            })

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but found {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual["timestamp"] == expected["timestamp"], f"Row {i+1} timestamp mismatch: expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual["level"] == expected["level"], f"Row {i+1} level mismatch: expected {expected['level']}, got {actual['level']}"
        assert actual["message"] == expected["message"], f"Row {i+1} message mismatch: expected {expected['message']}, got {actual['message']}"

def test_frontend_logs_json():
    assert os.path.isfile(FRONTEND_JSON), f"Expected JSON file {FRONTEND_JSON} is missing."

    expected_data = [
        {
            "timestamp": "2023-10-01 09:00:00",
            "level": "INFO",
            "message": "Service started"
        },
        {
            "timestamp": "2023-10-01 09:15:00",
            "level": "ERROR",
            "message": "Failed to render component"
        },
        {
            "timestamp": "2023-10-01 10:05:05",
            "level": "WARN",
            "message": "High latency detected"
        }
    ]

    with open(FRONTEND_JSON, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {FRONTEND_JSON} as JSON: {e}")

    assert isinstance(data, list), f"Expected JSON data to be a list, got {type(data).__name__}."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} JSON objects, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item {i} is not a JSON object."
        for key in ["timestamp", "level", "message"]:
            assert key in actual, f"Item {i} is missing key '{key}'"
            assert actual[key] == expected[key], f"Item {i} key '{key}' mismatch: expected {expected[key]}, got {actual[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
