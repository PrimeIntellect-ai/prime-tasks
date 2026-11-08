#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import unicodedata
import pytest

def test_processing_log():
    """Test that the processing.log file exists and contains the exact expected lines."""
    log_path = "/home/user/processing.log"
    assert os.path.exists(log_path), f"Log file {log_path} is missing."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."
    assert lines[0] == "Duplicates removed: 2", f"First line of log is incorrect. Found: {lines[0]}"
    assert lines[1] == "Imputed values: 2", f"Second line of log is incorrect. Found: {lines[1]}"

def test_sensors_clean_jsonl():
    """Test that the sensors_clean.jsonl file exists, is correctly formatted, sorted, and contains valid data."""
    jsonl_path = "/home/user/sensors_clean.jsonl"
    assert os.path.exists(jsonl_path), f"Output file {jsonl_path} is missing."
    assert os.path.isfile(jsonl_path), f"{jsonl_path} is not a file."

    records = []
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for i, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {i} in {jsonl_path} is not valid JSON: {line}")

    assert len(records) == 8, f"Expected 8 records in {jsonl_path}, found {len(records)}."

    expected_records = [
        {"date": "2023-10-01", "station": "München", "temp": 10.0},
        {"date": "2023-10-02", "station": "München", "temp": 12.0},
        {"date": "2023-10-03", "station": "München", "temp": 14.0},
        {"date": "2023-10-01", "station": "São Paulo", "temp": 25.0},
        {"date": "2023-10-02", "station": "São Paulo", "temp": 27.0},
        {"date": "2023-10-03", "station": "São Paulo", "temp": 29.0},
        {"date": "2023-10-04", "station": "東京", "temp": 15.0},
        {"date": "2023-10-05", "station": "東京", "temp": 18.0}
    ]

    for i, (actual, expected) in enumerate(zip(records, expected_records)):
        assert "date" in actual, f"Record {i+1} missing 'date' key."
        assert "station" in actual, f"Record {i+1} missing 'station' key."
        assert "temp" in actual, f"Record {i+1} missing 'temp' key."

        # Check NFC normalization
        assert unicodedata.is_normalized('NFC', actual["station"]), f"Station name '{actual['station']}' in record {i+1} is not NFC normalized."

        # Check values
        assert actual["date"] == expected["date"], f"Record {i+1} date mismatch: expected {expected['date']}, got {actual['date']}."
        assert actual["station"] == expected["station"], f"Record {i+1} station mismatch: expected {expected['station']}, got {actual['station']}."

        # Check temperature interpolation (float comparison)
        assert isinstance(actual["temp"], (int, float)), f"Record {i+1} temp is not a number."
        assert abs(actual["temp"] - expected["temp"]) < 1e-5, f"Record {i+1} temp mismatch: expected {expected['temp']}, got {actual['temp']}."

    # Check sorting explicitly
    stations = [r["station"] for r in records]
    dates = [r["date"] for r in records]

    sorted_records = sorted(records, key=lambda x: (x["station"], x["date"]))

    assert records == sorted_records, "The records are not sorted alphabetically by station and then chronologically by date."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
