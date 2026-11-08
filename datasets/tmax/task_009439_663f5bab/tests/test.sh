#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import sqlite3
import stat
import subprocess
from collections import Counter, defaultdict

import pytest

DB_PATH = "/home/user/sensor_data.db"
SCRIPT_PATH = "/home/user/detect_anomalies.sh"
ANOMALIES_PATH = "/home/user/anomalies.csv"
RAW_DATA_PATH = "/home/user/raw_data"
EXPECTED_HEADER = ["sensor_id", "timestamp", "temperature", "previous_temperature"]


def read_source_rows():
    rows = []
    source_files = sorted(
        os.path.join(RAW_DATA_PATH, name)
        for name in os.listdir(RAW_DATA_PATH)
        if name.endswith(".csv")
    )
    assert source_files, "No source CSV files were found."

    for path in source_files:
        with open(path, "r", encoding="utf-16le", newline="") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == ["timestamp", "sensor_id", "temperature"], (
                f"Unexpected header in {path}: {header}"
            )
            for row in reader:
                if not row:
                    continue
                assert len(row) == 3, f"Malformed source row in {path}: {row}"
                rows.append((row[0], row[1], float(row[2])))
    return rows


def database_rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute(
            "SELECT timestamp, sensor_id, temperature FROM readings"
        ).fetchall()
    finally:
        conn.close()


def derive_anomalies(rows):
    by_sensor = defaultdict(list)
    for timestamp, sensor_id, temperature in rows:
        by_sensor[sensor_id].append((timestamp, float(temperature)))

    anomalies = []
    for sensor_id, values in by_sensor.items():
        values.sort(key=lambda item: item[0])
        for index in range(1, len(values)):
            timestamp, temperature = values[index]
            previous_temperature = values[index - 1][1]
            if abs(temperature - previous_temperature) > 15.0:
                anomalies.append(
                    (sensor_id, timestamp, temperature, previous_temperature)
                )
    anomalies.sort(key=lambda row: (row[1], row[0]))
    return anomalies


def run_script():
    if os.path.exists(ANOMALIES_PATH):
        os.remove(ANOMALIES_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Anomaly script failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(ANOMALIES_PATH), (
        f"Script did not create {ANOMALIES_PATH}."
    )


def read_anomaly_csv():
    with open(ANOMALIES_PATH, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "Anomaly CSV is empty."
    assert rows[0] == EXPECTED_HEADER, (
        f"Expected header {EXPECTED_HEADER}, got {rows[0]}"
    )

    parsed = []
    for row in rows[1:]:
        assert len(row) == 4, f"Malformed anomaly CSV row: {row}"
        parsed.append((row[0], row[1], float(row[2]), float(row[3])))
    return parsed


def test_database_exists_and_schema():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings';")
    assert cursor.fetchone() is not None, "Table 'readings' does not exist in the database."

    cursor.execute("PRAGMA table_info(readings);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    assert "timestamp" in columns and columns["timestamp"] == "TEXT", "Column 'timestamp' missing or not TEXT."
    assert "sensor_id" in columns and columns["sensor_id"] == "TEXT", "Column 'sensor_id' missing or not TEXT."
    assert "temperature" in columns and columns["temperature"] == "REAL", "Column 'temperature' missing or not REAL."

    conn.close()


def test_database_contents():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT COUNT(*) FROM readings;")
        count = cursor.fetchone()[0]
        assert count == 8, f"Expected 8 rows in 'readings' table, found {count}."

        cursor.execute("SELECT temperature FROM readings WHERE sensor_id='sensor_1' AND timestamp='2023-10-01T00:02:00Z';")
        temp = cursor.fetchone()
        assert temp is not None, "Expected reading for sensor_1 at 2023-10-01T00:02:00Z is missing."
        assert abs(temp[0] - 38.0) < 0.01, f"Expected temperature 38.0, found {temp[0]}."
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query the database: {e}")
    finally:
        conn.close()

    expected = Counter(read_source_rows())
    actual = Counter(
        (timestamp, sensor_id, float(temperature))
        for timestamp, sensor_id, temperature in database_rows()
    )
    assert actual == expected, (
        "The readings table does not exactly contain all rows from the UTF-16LE source CSV files."
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the owner."


def test_script_executes_and_derives_current_anomalies():
    run_script()
    actual = read_anomaly_csv()
    expected = derive_anomalies(database_rows())
    assert actual == expected, (
        f"Script output does not match anomalies derived from the database. "
        f"Expected {expected}, got {actual}."
    )


def test_anomalies_csv():
    assert os.path.exists(ANOMALIES_PATH), f"Output file {ANOMALIES_PATH} is missing."
    assert os.path.isfile(ANOMALIES_PATH), f"{ANOMALIES_PATH} is not a file."

    with open(ANOMALIES_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "sensor_id,timestamp,temperature,previous_temperature",
        "sensor_1,2023-10-01T00:02:00Z,38.0,21.5",
        "sensor_2,2023-10-01T00:02:30Z,-5.0,14.0"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {ANOMALIES_PATH}, found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"


def test_script_handles_changed_database_and_threshold_boundary():
    snapshot_path = "/tmp/sensor_data_verifier_snapshot.db"
    if os.path.exists(snapshot_path):
        os.remove(snapshot_path)

    source = sqlite3.connect(DB_PATH)
    snapshot = sqlite3.connect(snapshot_path)
    try:
        source.backup(snapshot)
    finally:
        snapshot.close()
        source.close()

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.executemany(
                "INSERT INTO readings(timestamp, sensor_id, temperature) VALUES (?, ?, ?)",
                [
                    ("2024-01-01T00:00:00Z", "dynamic_z", 10.0),
                    ("2024-01-01T00:01:00Z", "dynamic_z", 25.0),
                    ("2024-01-01T00:02:00Z", "dynamic_z", 40.25),
                    ("2024-01-01T00:00:30Z", "dynamic_a", 100.0),
                    ("2024-01-01T00:01:30Z", "dynamic_a", 80.0),
                ],
            )
            conn.commit()
        finally:
            conn.close()

        expected = derive_anomalies(database_rows())
        run_script()
        actual = read_anomaly_csv()
        assert actual == expected, (
            "The script did not recompute anomalies for changed database contents, "
            "or mishandled ordering/the strict 15.0-degree threshold. "
            f"Expected {expected}, got {actual}."
        )
    finally:
        restored = sqlite3.connect(DB_PATH)
        snapshot = sqlite3.connect(snapshot_path)
        try:
            snapshot.backup(restored)
        finally:
            restored.close()
            snapshot.close()
        os.remove(snapshot_path)
        if os.path.exists(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
            subprocess.run([SCRIPT_PATH], cwd="/home/user", timeout=20, check=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
