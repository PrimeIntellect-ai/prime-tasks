#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import sqlite3
import math
import re
import pytest

DATA_DIR = "/home/user/sensor_data"
DB_PATH = "/home/user/anomalies.db"
LOG_PATH = "/home/user/pipeline.log"

def get_expected_anomalies():
    """Dynamically compute the expected anomalies from the CSV files."""
    if not os.path.exists(DATA_DIR):
        return [], 0

    all_rows = []
    total_rows = 0
    for file_name in os.listdir(DATA_DIR):
        if file_name.endswith('.csv'):
            with open(os.path.join(DATA_DIR, file_name), 'r', newline='') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    all_rows.append(row)
                    total_rows += 1

    # Group by sensor_id
    sensors = {}
    for row in all_rows:
        s_id = row['sensor_id']
        temp = float(row['temperature'])
        if s_id not in sensors:
            sensors[s_id] = []
        sensors[s_id].append((row['timestamp'], temp))

    anomalies = []
    for s_id, readings in sensors.items():
        n = len(readings)
        if n == 0:
            continue
        mean = sum(t for _, t in readings) / n
        variance = sum((t - mean) ** 2 for _, t in readings) / n
        std_dev = math.sqrt(variance)

        for ts, temp in readings:
            if std_dev > 0 and abs(temp - mean) > 2 * std_dev:
                z_score = round((temp - mean) / std_dev, 2)
                anomalies.append({
                    'timestamp': ts,
                    'sensor_id': s_id,
                    'temperature': temp,
                    'z_score': z_score
                })

    return anomalies, total_rows

def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created."

def test_database_schema_and_contents():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    expected_anomalies, _ = get_expected_anomalies()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='temperature_anomalies';")
    assert cursor.fetchone() is not None, "Table 'temperature_anomalies' does not exist in the database."

    # Check columns
    cursor.execute("PRAGMA table_info(temperature_anomalies);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    assert 'timestamp' in columns, "Column 'timestamp' is missing."
    assert 'sensor_id' in columns, "Column 'sensor_id' is missing."
    assert 'temperature' in columns, "Column 'temperature' is missing."
    assert 'z_score' in columns, "Column 'z_score' is missing."

    # Check contents
    cursor.execute("SELECT timestamp, sensor_id, temperature, z_score FROM temperature_anomalies ORDER BY sensor_id, timestamp;")
    db_rows = cursor.fetchall()
    conn.close()

    assert len(db_rows) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies, found {len(db_rows)}."

    # Sort both lists to compare
    expected_sorted = sorted(expected_anomalies, key=lambda x: (x['sensor_id'], x['timestamp']))
    for db_row, exp_row in zip(db_rows, expected_sorted):
        assert db_row[0] == exp_row['timestamp'], f"Timestamp mismatch: expected {exp_row['timestamp']}, got {db_row[0]}"
        assert db_row[1] == exp_row['sensor_id'], f"Sensor ID mismatch: expected {exp_row['sensor_id']}, got {db_row[1]}"
        assert math.isclose(db_row[2], exp_row['temperature'], rel_tol=1e-5), f"Temperature mismatch: expected {exp_row['temperature']}, got {db_row[2]}"
        assert math.isclose(db_row[3], exp_row['z_score'], rel_tol=1e-5), f"Z-score mismatch: expected {exp_row['z_score']}, got {db_row[3]}"

def test_pipeline_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."

    expected_anomalies, total_rows = get_expected_anomalies()
    num_anomalies = len(expected_anomalies)

    with open(LOG_PATH, 'r') as f:
        log_content = f.read()

    # Check for INGESTION step
    ingestion_pattern = rf"\[.*?\] - INGESTION - Processed {total_rows} rows"
    assert re.search(ingestion_pattern, log_content), f"Log does not contain expected INGESTION message for {total_rows} rows."

    # Check for ANOMALY_DETECTION step
    detection_pattern = rf"\[.*?\] - ANOMALY_DETECTION - Found {num_anomalies} anomalies"
    assert re.search(detection_pattern, log_content), f"Log does not contain expected ANOMALY_DETECTION message for {num_anomalies} anomalies."

    # Check for EXPORT step
    export_pattern = r"\[.*?\] - EXPORT - Successfully exported to SQLite"
    assert re.search(export_pattern, log_content), "Log does not contain expected EXPORT message."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
