#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = '/home/user/data/sensors.db'
CSV_PATH = '/home/user/data/sensor_log.csv'
SCRIPT_PATH = '/home/user/process_sensors.py'


def run_pipeline():
    subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        check=True,
        timeout=60,
    )


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_script():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    run_pipeline()
    assert os.path.isfile(DB_PATH), f"Script did not create database at {DB_PATH}"


def get_db_connection():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"


def test_table_schema_and_row_count():
    conn = get_db_connection()
    c = conn.cursor()

    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings'")
    assert c.fetchone() is not None, "Table 'readings' does not exist in the database."

    c.execute("PRAGMA table_info(readings)")
    columns = {row['name'] for row in c.fetchall()}
    expected_columns = {'sensor_id', 'timestamp', 'temperature', 'notes', 'is_anomaly'}
    assert expected_columns.issubset(columns), f"Table 'readings' is missing expected columns. Found: {columns}"

    c.execute("SELECT COUNT(*) as cnt FROM readings")
    count = c.fetchone()['cnt']
    assert count == 5, f"Expected 5 rows in 'readings' table, found {count}."
    conn.close()


def test_timestamps_and_anomalies():
    conn = get_db_connection()
    c = conn.cursor()

    expected_data = [
        ('S1', '2023-10-01T14:00:00Z', 0),
        ('S1', '2023-10-01T14:30:00Z', 1),
        ('S1', '2023-10-01T16:00:00Z', 0),
        ('S2', '2023-10-01T14:05:00Z', 0),
        ('S2', '2023-10-01T15:10:00Z', 0),
    ]

    for sensor_id, timestamp, expected_anomaly in expected_data:
        c.execute(
            "SELECT is_anomaly FROM readings WHERE sensor_id=? AND timestamp=?",
            (sensor_id, timestamp),
        )
        row = c.fetchone()
        assert row is not None, f"Missing reading for sensor {sensor_id} at {timestamp}. Check timestamp formatting and UTC conversion."
        anomaly_val = int(row['is_anomaly'])
        assert anomaly_val == expected_anomaly, f"Expected is_anomaly={expected_anomaly} for {sensor_id} at {timestamp}, got {anomaly_val}."
    conn.close()


def test_embedded_newline_in_notes():
    conn = get_db_connection()
    c = conn.cursor()

    c.execute("SELECT notes FROM readings WHERE sensor_id='S2' AND timestamp='2023-10-01T14:05:00Z'")
    row = c.fetchone()
    assert row is not None, "Missing reading for S2 at 2023-10-01T14:05:00Z"

    notes = row['notes']
    assert "\n" in notes, f"Expected embedded newline in notes for S2 at 14:05:00Z, but got: {repr(notes)}. CSV parsing may have dropped or corrupted the row."
    conn.close()


def test_all_original_values_are_preserved():
    expected = {
        ('S1', '2023-10-01T14:00:00Z'): (22.5, 'Normal reading', 0),
        ('S1', '2023-10-01T14:30:00Z'): (45.0, 'Spike detected', 1),
        ('S1', '2023-10-01T16:00:00Z'): (44.0, 'Still hot', 0),
        ('S2', '2023-10-01T14:05:00Z'): (18.0, 'Sensor restarted\nNeeds calibration', 0),
        ('S2', '2023-10-01T15:10:00Z'): (18.5, 'Normal', 0),
    }

    conn = get_db_connection()
    rows = conn.execute(
        'SELECT sensor_id, timestamp, temperature, notes, is_anomaly FROM readings'
    ).fetchall()
    conn.close()

    assert len(rows) == len(expected)
    actual_keys = {(row['sensor_id'], row['timestamp']) for row in rows}
    assert actual_keys == set(expected)
    for row in rows:
        key = (row['sensor_id'], row['timestamp'])
        temperature, notes, anomaly = expected[key]
        assert float(row['temperature']) == pytest.approx(temperature)
        assert row['notes'] == notes
        assert int(row['is_anomaly']) == anomaly


def test_pipeline_on_unseen_csv_data():
    original_csv = open(CSV_PATH, 'rb').read()
    token = secrets.token_hex(6)
    sensor_a = f'A_{token}'
    sensor_b = f'B_{token}'
    base_a = secrets.randbelow(200) / 10.0 + 10.0
    base_b = secrets.randbelow(200) / 10.0 + 30.0

    records = [
        [sensor_a, '2024-02-03 18:00:00+02:00', base_a + 40.5, f'last,{token}'],
        [sensor_b, '2024-02-03T09:15:00-05:00', base_b - 25.0, f'sudden "drop" {token}'],
        [sensor_a, '2024-02-03 10:00:00-05:00', base_a, f'first line {token}\nsecond line'],
        [sensor_b, '2024-02-03T17:00:00+02:00', base_b - 24.0, f'recovered {token}'],
        [sensor_a, '2024-02-03T15:30:00Z', base_a + 20.0, f'exact threshold {token}'],
        [sensor_b, '2024-02-03T14:00:00Z', base_b, f'initial {token}'],
    ]
    expected = {
        (sensor_a, '2024-02-03T15:00:00Z'): (base_a, f'first line {token}\nsecond line', 0),
        (sensor_a, '2024-02-03T15:30:00Z'): (base_a + 20.0, f'exact threshold {token}', 0),
        (sensor_a, '2024-02-03T16:00:00Z'): (base_a + 40.5, f'last,{token}', 1),
        (sensor_b, '2024-02-03T14:00:00Z'): (base_b, f'initial {token}', 0),
        (sensor_b, '2024-02-03T14:15:00Z'): (base_b - 25.0, f'sudden "drop" {token}', 1),
        (sensor_b, '2024-02-03T15:00:00Z'): (base_b - 24.0, f'recovered {token}', 0),
    }

    try:
        with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['sensor_id', 'timestamp', 'temperature', 'notes'])
            writer.writerows(records)

        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        run_pipeline()

        conn = get_db_connection()
        rows = conn.execute(
            'SELECT sensor_id, timestamp, temperature, notes, is_anomaly FROM readings'
        ).fetchall()
        conn.close()

        assert len(rows) == len(expected)
        actual_keys = {(row['sensor_id'], row['timestamp']) for row in rows}
        assert actual_keys == set(expected)
        for row in rows:
            key = (row['sensor_id'], row['timestamp'])
            temperature, notes, anomaly = expected[key]
            assert float(row['temperature']) == pytest.approx(temperature)
            assert row['notes'] == notes
            assert int(row['is_anomaly']) == anomaly
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
