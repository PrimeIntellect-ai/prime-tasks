#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

OUTPUT_DIR = "/home/user/output"
CLEAN_READINGS_FILE = os.path.join(OUTPUT_DIR, "clean_readings.csv")
REPORT_FILE = os.path.join(OUTPUT_DIR, "report.txt")

def test_clean_readings_exists():
    """Test that clean_readings.csv was created."""
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} does not exist."
    assert os.path.isfile(CLEAN_READINGS_FILE), f"File {CLEAN_READINGS_FILE} does not exist."

def test_clean_readings_content():
    """Test the header and contents of clean_readings.csv."""
    assert os.path.isfile(CLEAN_READINGS_FILE), f"File {CLEAN_READINGS_FILE} does not exist."

    with open(CLEAN_READINGS_FILE, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{CLEAN_READINGS_FILE} is empty."

    header = rows[0]
    expected_header = ["reading_id", "sensor_id", "location", "value"]
    assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected 4 data rows, got {len(data_rows)}."

    expected_data = {
        ("R001", "101", "Zone_A", "45.5"),
        ("R003", "102", "Zone_B", "42.1"),
        ("R005", "101", "Zone_A", "46.0"),
        ("R007", "105", "Zone_D", "8.4")
    }

    actual_data = set()
    for row in data_rows:
        assert len(row) == 4, f"Row {row} does not have exactly 4 columns."
        # Ensure sensor_id is not a float string like "101.0"
        assert "." not in row[1], f"sensor_id {row[1]} appears to be a float."

        # Add to set as a tuple for unordered comparison
        # Note: We parse value to float and format to handle minor formatting differences like 46.0 vs 46
        try:
            val = float(row[3])
            val_str = f"{val:.1f}"
        except ValueError:
            val_str = row[3]

        actual_data.add((row[0], row[1], row[2], val_str))

    assert actual_data == expected_data, f"Data mismatch. Expected {expected_data}, got {actual_data}."

def test_report_exists_and_content():
    """Test that report.txt exists and contains the correct summary."""
    assert os.path.isfile(REPORT_FILE), f"File {REPORT_FILE} does not exist."

    with open(REPORT_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, f"Expected exactly 2 lines in {REPORT_FILE}, got {len(content)}."

    assert content[0].strip() == "Total valid readings: 4", f"First line mismatch in {REPORT_FILE}. Got: {content[0]}"
    assert content[1].strip() == "Sum of values: 142.0", f"Second line mismatch in {REPORT_FILE}. Got: {content[1]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
