#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime as dt
import os
import re
import sqlite3
import subprocess

import pytest
import requests

API_URL = "http://127.0.0.1:8055/query"
TOKEN = "secr3t_T0k3n_99"
DB_PATH = "/home/user/processed.db"
CSV_PATH = "/home/user/raw_sensors.csv"
CONFIG_PATH = "/app/config.png"


def read_interval_minutes():
    text = subprocess.check_output(
        ["tesseract", CONFIG_PATH, "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    match = re.search(r"INTERVAL\s*:\s*(\d+)\s*min", text, re.IGNORECASE)
    assert match, f"Could not extract aggregation interval from config image. OCR output: {text!r}"
    return int(match.group(1))


def expected_etl_rows():
    interval = read_interval_minutes()
    parsed = []
    seen = set()

    with open(CSV_PATH, newline="") as f:
        for row in csv.DictReader(f):
            timestamp = dt.datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S")
            key = (timestamp, row["sensor_id"])
            if key in seen:
                continue
            seen.add(key)
            value_text = row["value"].strip()
            parsed.append({
                "timestamp": timestamp,
                "sensor_id": row["sensor_id"],
                "value": None if value_text == "" else float(value_text),
            })

    by_sensor = {}
    for row in parsed:
        by_sensor.setdefault(row["sensor_id"], []).append(row)

    interpolated = []
    for sensor_id, rows in by_sensor.items():
        rows.sort(key=lambda r: r["timestamp"])
        for i, row in enumerate(rows):
            if row["value"] is None:
                previous = next((rows[j] for j in range(i - 1, -1, -1) if rows[j]["value"] is not None), None)
                following = next((rows[j] for j in range(i + 1, len(rows)) if rows[j]["value"] is not None), None)
                assert previous is not None and following is not None, "Test fixture has an unsupported edge null"
                total = (following["timestamp"] - previous["timestamp"]).total_seconds()
                elapsed = (row["timestamp"] - previous["timestamp"]).total_seconds()
                row["value"] = previous["value"] + (following["value"] - previous["value"]) * elapsed / total
            interpolated.append(row)

    buckets = {}
    bucket_seconds = interval * 60
    epoch = dt.datetime(1970, 1, 1)
    for row in interpolated:
        seconds = int((row["timestamp"] - epoch).total_seconds())
        bucket = epoch + dt.timedelta(seconds=(seconds // bucket_seconds) * bucket_seconds)
        key = (bucket.strftime("%Y-%m-%d %H:%M:%S"), row["sensor_id"])
        buckets.setdefault(key, []).append(row["value"])

    return sorted(
        (time_bucket, sensor_id, sum(values) / len(values))
        for (time_bucket, sensor_id), values in buckets.items()
    )


def authorized_query(sensor_id):
    try:
        return requests.get(
            API_URL,
            params={"sensor_id": sensor_id},
            headers={"Authorization": f"Bearer {TOKEN}"},
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")


def test_database_exists_and_schema():
    """Verify that the SQLite database is created and has the correct schema."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sensor_data';")
    assert cursor.fetchone() is not None, "Table 'sensor_data' does not exist in the database."

    cursor.execute("PRAGMA table_info(sensor_data);")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    assert "time_bucket" in columns, "Column 'time_bucket' missing."
    assert "sensor_id" in columns, "Column 'sensor_id' missing."
    assert "avg_value" in columns, "Column 'avg_value' missing."

    conn.close()


def test_database_contains_complete_derived_etl_output():
    expected = expected_etl_rows()
    with sqlite3.connect(DB_PATH) as conn:
        actual = conn.execute(
            "SELECT time_bucket, sensor_id, avg_value FROM sensor_data ORDER BY time_bucket, sensor_id"
        ).fetchall()

    assert len(actual) == len(expected), f"Expected {len(expected)} processed rows, got {len(actual)}: {actual!r}"
    for got, want in zip(actual, expected):
        assert got[0] == want[0]
        assert got[1] == want[1]
        assert abs(float(got[2]) - want[2]) < 1e-5


def test_api_unauthorized():
    """Verify that the API returns 401 when no token or incorrect token is provided."""
    try:
        response = requests.get(f"{API_URL}?sensor_id=S1", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}."

    try:
        response = requests.get(
            f"{API_URL}?sensor_id=S1",
            headers={"Authorization": "Bearer wrong_token"},
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized with wrong token, got {response.status_code}."


def test_api_authorized_and_data_correct():
    """Verify that the API returns the correct aggregated data for S1."""
    response = authorized_query("S1")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("API response is not valid JSON.")

    assert isinstance(data, list), "Expected response to be a JSON array."

    expected_data = [
        {"time": "2023-10-01 10:00:00", "value": 16.75},
        {"time": "2023-10-01 10:15:00", "value": 30.0},
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}."
    for i, expected in enumerate(expected_data):
        assert "time" in data[i], f"Record {i} missing 'time' key."
        assert "value" in data[i], f"Record {i} missing 'value' key."
        assert data[i]["time"] == expected["time"], f"Expected time {expected['time']}, got {data[i]['time']}."
        assert abs(data[i]["value"] - expected["value"]) < 1e-5, f"Expected value {expected['value']}, got {data[i]['value']}."


def test_api_returns_every_sensor_from_derived_output():
    expected_rows = expected_etl_rows()
    by_sensor = {}
    for time_bucket, sensor_id, value in expected_rows:
        by_sensor.setdefault(sensor_id, []).append({"time": time_bucket, "value": value})

    for sensor_id, expected in by_sensor.items():
        response = authorized_query(sensor_id)
        assert response.status_code == 200, response.text
        data = response.json()
        assert isinstance(data, list)
        assert len(data) == len(expected), f"Wrong number of API rows for {sensor_id}: {data!r}"
        for got, want in zip(data, expected):
            assert got["time"] == want["time"]
            assert abs(float(got["value"]) - want["value"]) < 1e-5


def test_api_queries_live_database_and_sorts_results():
    sensor_id = "__verifier_live_probe__"
    probe_rows = [
        ("2099-01-01 00:15:00", sensor_id, 91.25),
        ("2099-01-01 00:00:00", sensor_id, -7.5),
    ]

    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("DELETE FROM sensor_data WHERE sensor_id = ?", (sensor_id,))
        conn.executemany(
            "INSERT INTO sensor_data(time_bucket, sensor_id, avg_value) VALUES (?, ?, ?)",
            probe_rows,
        )
        conn.commit()

    try:
        response = authorized_query(sensor_id)
        assert response.status_code == 200, response.text
        assert response.json() == [
            {"time": "2099-01-01 00:00:00", "value": -7.5},
            {"time": "2099-01-01 00:15:00", "value": 91.25},
        ]
    finally:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute("DELETE FROM sensor_data WHERE sensor_id = ?", (sensor_id,))
            conn.commit()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
