#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import csv
from collections import defaultdict

SUMMARY_FILE = "/home/user/summary.json"
DB_FILE = "/home/user/data/observations.db"
CSV_FILE = "/home/user/data/calibration.csv"

def test_summary_json_exists():
    assert os.path.isfile(SUMMARY_FILE), f"Expected output file {SUMMARY_FILE} does not exist."

def test_summary_json_content():
    # Load actual data
    with open(SUMMARY_FILE, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_FILE} is not a valid JSON.")

    assert isinstance(actual_data, list), "The JSON root must be an array."

    # Recompute expected data from sources
    assert os.path.isfile(DB_FILE), f"Database file {DB_FILE} is missing."
    assert os.path.isfile(CSV_FILE), f"CSV file {CSV_FILE} is missing."

    # Read calibrations
    calibrations = {}
    with open(CSV_FILE, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            calibrations[int(row['sensor_id'])] = float(row['correction_factor'])

    # Read database
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    c.execute("SELECT sensor_id, sensor_type FROM sensors")
    sensors = {row[0]: row[1] for row in c.fetchall()}

    c.execute("SELECT sensor_id, timestamp, raw_value FROM readings")
    readings = c.fetchall()
    conn.close()

    # Aggregate data
    groups = defaultdict(list)
    for sensor_id, timestamp, raw_value in readings:
        date = timestamp.split()[0]
        sensor_type = sensors[sensor_id]
        correction_factor = calibrations.get(sensor_id, 1.0)
        corrected_value = raw_value * correction_factor
        groups[(date, sensor_type)].append(corrected_value)

    expected_data = []
    for (date, sensor_type), values in groups.items():
        max_val = round(max(values), 2)
        min_val = round(min(values), 2)
        avg_val = round(sum(values) / len(values), 2)

        expected_data.append({
            "date": date,
            "sensor_type": sensor_type,
            "max_val": max_val,
            "min_val": min_val,
            "avg_val": avg_val
        })

    # Sort expected data
    expected_data.sort(key=lambda x: (x["date"], x["sensor_type"]))

    # Compare lengths
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} objects in JSON, found {len(actual_data)}."

    # Compare contents
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."

        # Check keys
        expected_keys = {"date", "sensor_type", "max_val", "min_val", "avg_val"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        # Check values
        assert actual["date"] == expected["date"], f"Item at index {i}: expected date {expected['date']}, got {actual['date']}."
        assert actual["sensor_type"] == expected["sensor_type"], f"Item at index {i}: expected sensor_type {expected['sensor_type']}, got {actual['sensor_type']}."
        assert actual["max_val"] == expected["max_val"], f"Item at index {i}: expected max_val {expected['max_val']}, got {actual['max_val']}."
        assert actual["min_val"] == expected["min_val"], f"Item at index {i}: expected min_val {expected['min_val']}, got {actual['min_val']}."
        assert actual["avg_val"] == expected["avg_val"], f"Item at index {i}: expected avg_val {expected['avg_val']}, got {actual['avg_val']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
