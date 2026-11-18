#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import sqlite3
import stat
import subprocess
from collections import Counter

DB_PATH = "/home/user/sensors.db"
SCRIPT_PATH = "/home/user/get_latest.sh"
CSV_PATH = "/home/user/readings.csv"

EXPECTED_ROWS = [
    ("SENS-01", "2023-10-01T10:00:00Z", 20.0, 50.0),
    ("SENS-02", "2023-10-01T10:00:00Z", 22.0, 45.0),
    ("SENS-02", "2023-10-01T12:00:00Z", 23.5, 44.0),
    ("SENS-02", "2023-10-01T12:00:00Z", 24.0, 42.0),
    ("SENS-03", "2023-10-02T08:00:00Z", 19.0, 55.0),
    ("SENS-03", "2023-10-02T07:00:00Z", 25.0, 60.0),
]


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."


def test_database_table_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings';")
        table = cursor.fetchone()
        assert table is not None, "Table 'readings' does not exist in the database."
        cursor.execute("SELECT COUNT(*) FROM readings;")
        count = cursor.fetchone()[0]
        assert count > 0, "Table 'readings' is empty."
    finally:
        conn.close()


def test_csv_was_imported_correctly():
    with open(CSV_PATH, newline="") as f:
        reader = csv.DictReader(f)
        csv_rows = [
            (r["sensor_id"], r["timestamp"], float(r["temperature"]), float(r["humidity"]))
            for r in reader
        ]
    assert Counter(csv_rows) == Counter(EXPECTED_ROWS), "The source CSV was modified."

    conn = sqlite3.connect(DB_PATH)
    try:
        columns = {row[1] for row in conn.execute("PRAGMA table_info(readings)")}
        assert {"sensor_id", "timestamp", "temperature", "humidity"}.issubset(columns), \
            "The readings table is missing required columns."
        rows = conn.execute(
            'SELECT sensor_id, timestamp, temperature, humidity FROM readings'
        ).fetchall()
        normalized = [
            (str(sensor_id), str(timestamp), float(temperature), float(humidity))
            for sensor_id, timestamp, temperature, humidity in rows
        ]
        assert Counter(normalized) == Counter(EXPECTED_ROWS), \
            "The readings table is not an exact import of readings.csv."
    finally:
        conn.close()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def run_script(sensor_id):
    result = subprocess.run([SCRIPT_PATH, sensor_id], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, \
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    output = result.stdout.strip()
    assert output, "Script produced no output."
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        assert False, f"Script output is not valid JSON. Output: {output}"


def test_script_output_sens_02():
    data = run_script("SENS-02")
    expected_data = {
        "id": "SENS-02",
        "latest_reading": {
            "time": "2023-10-01T12:00:00Z",
            "temp": 24,
            "hum": 42
        }
    }
    assert data.get("id") == expected_data["id"], "Incorrect sensor ID in output."
    assert "latest_reading" in data, "Missing 'latest_reading' in output."
    assert data["latest_reading"].get("time") == expected_data["latest_reading"]["time"], "Incorrect time in output."
    assert float(data["latest_reading"].get("temp", 0)) == float(expected_data["latest_reading"]["temp"]), "Incorrect temperature in output."
    assert float(data["latest_reading"].get("hum", 0)) == float(expected_data["latest_reading"]["hum"]), "Incorrect humidity in output."


def test_script_output_sens_03():
    data = run_script("SENS-03")
    expected_data = {
        "id": "SENS-03",
        "latest_reading": {
            "time": "2023-10-02T08:00:00Z",
            "temp": 19,
            "hum": 55
        }
    }
    assert data.get("id") == expected_data["id"], "Incorrect sensor ID in output."
    assert "latest_reading" in data, "Missing 'latest_reading' in output."
    assert data["latest_reading"].get("time") == expected_data["latest_reading"]["time"], "Incorrect time in output."
    assert float(data["latest_reading"].get("temp", 0)) == float(expected_data["latest_reading"]["temp"]), "Incorrect temperature in output."
    assert float(data["latest_reading"].get("hum", 0)) == float(expected_data["latest_reading"]["hum"]), "Incorrect humidity in output."


def test_script_queries_arbitrary_sensor_and_handles_ties_safely():
    token = secrets.token_hex(12)
    sensor_id = f"DYN-' $() ; -- {token}"
    day = 10 + secrets.randbelow(15)
    old_time = f"2025-04-{day:02d}T08:00:00Z"
    max_time = f"2025-04-{day:02d}T19:30:00Z"
    winning_temp = 40.0 + secrets.randbelow(4000) / 100.0
    lower_temp = winning_temp - 1.25
    stale_temp = winning_temp + 100.0
    winning_hum = 10.0 + secrets.randbelow(7000) / 100.0

    rows = [
        (sensor_id, max_time, lower_temp, winning_hum + 1.0),
        (sensor_id, max_time, winning_temp, winning_hum),
        (sensor_id, old_time, stale_temp, winning_hum + 2.0),
    ]
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany(
            'INSERT INTO readings (sensor_id, timestamp, temperature, humidity) VALUES (?, ?, ?, ?)',
            rows,
        )
        conn.commit()
        data = run_script(sensor_id)
    finally:
        conn.execute('DELETE FROM readings WHERE sensor_id = ?', (sensor_id,))
        conn.commit()
        conn.close()

    assert isinstance(data, dict), "Output must be a JSON object."
    assert set(data) == {"id", "latest_reading"}, "Output does not match the required top-level schema."
    assert data["id"] == sensor_id, "Script did not handle the supplied sensor ID safely."
    reading = data["latest_reading"]
    assert isinstance(reading, dict), "latest_reading must be a JSON object."
    assert set(reading) == {"time", "temp", "hum"}, "latest_reading does not match the required schema."
    assert reading["time"] == max_time, "Script did not select the maximum timestamp."
    assert isinstance(reading["temp"], (int, float)) and not isinstance(reading["temp"], bool), \
        "Temperature must be a JSON number."
    assert isinstance(reading["hum"], (int, float)) and not isinstance(reading["hum"], bool), \
        "Humidity must be a JSON number."
    assert float(reading["temp"]) == winning_temp, "Script did not resolve the timestamp tie by highest temperature."
    assert float(reading["hum"]) == winning_hum, "Humidity was not taken from the selected row."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
