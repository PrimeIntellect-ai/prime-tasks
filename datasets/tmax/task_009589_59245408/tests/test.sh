#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import csv
import math
import pytest

CLEAN_DB_PATH = "/home/user/clean_data.db"
ANOMALIES_CSV_PATH = "/home/user/anomalies.csv"

def test_clean_db_exists():
    assert os.path.exists(CLEAN_DB_PATH), f"Database file {CLEAN_DB_PATH} does not exist."
    assert os.path.isfile(CLEAN_DB_PATH), f"{CLEAN_DB_PATH} is not a file."

def test_clean_sensor_table_schema_and_data():
    conn = sqlite3.connect(CLEAN_DB_PATH)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='clean_sensor'")
    table = cursor.fetchone()
    assert table is not None, "Table 'clean_sensor' does not exist in the clean database."

    # Check columns
    cursor.execute("PRAGMA table_info(clean_sensor)")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
    assert "timestamp" in columns, "Column 'timestamp' missing from 'clean_sensor' table."
    assert "temperature_c" in columns, "Column 'temperature_c' missing from 'clean_sensor' table."
    assert "pressure" in columns, "Column 'pressure' missing from 'clean_sensor' table."
    assert "is_anomaly" in columns, "Column 'is_anomaly' missing from 'clean_sensor' table."

    # Fetch all data
    cursor.execute("SELECT timestamp, temperature_c, pressure, is_anomaly FROM clean_sensor ORDER BY timestamp")
    rows = cursor.fetchall()

    expected_rows = [
        ('2023-01-01 00:00:00', 15.0, '1000', 0),
        ('2023-01-01 00:05:00', 15.0, '1001', 0),
        ('2023-01-01 00:10:00', 30.0, '1002', 1),
        ('2023-01-01 00:15:00', 25.0, '1003', 0),
        ('2023-01-01 00:20:00', 14.0, '1004', 1)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, found {len(rows)}."

    for i, (row, expected) in enumerate(zip(rows, expected_rows)):
        assert row[0] == expected[0], f"Row {i}: Expected timestamp {expected[0]}, got {row[0]}"
        assert math.isclose(float(row[1]), expected[1], abs_tol=0.1), f"Row {i}: Expected temperature_c {expected[1]}, got {row[1]}"
        assert str(row[2]) == expected[2], f"Row {i}: Expected pressure {expected[2]}, got {row[2]}"
        assert int(row[3]) == expected[3], f"Row {i}: Expected is_anomaly {expected[3]}, got {row[3]}"

    conn.close()

def test_anomalies_csv():
    assert os.path.exists(ANOMALIES_CSV_PATH), f"CSV file {ANOMALIES_CSV_PATH} does not exist."
    assert os.path.isfile(ANOMALIES_CSV_PATH), f"{ANOMALIES_CSV_PATH} is not a file."

    with open(ANOMALIES_CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    assert [h.strip() for h in header] == ['timestamp', 'temperature_c', 'pressure'], "CSV header is incorrect."

    data_rows = rows[1:]
    expected_data = [
        ['2023-01-01 00:10:00', 30.0, '1002'],
        ['2023-01-01 00:20:00', 14.0, '1004']
    ]

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows in CSV, found {len(data_rows)}."

    for i, (row, expected) in enumerate(zip(data_rows, expected_data)):
        assert row[0].strip() == expected[0], f"CSV Row {i}: Expected timestamp {expected[0]}, got {row[0]}"
        assert math.isclose(float(row[1]), expected[1], abs_tol=0.1), f"CSV Row {i}: Expected temperature_c {expected[1]}, got {row[1]}"
        assert row[2].strip() == expected[2], f"CSV Row {i}: Expected pressure {expected[2]}, got {row[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
