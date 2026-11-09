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
import glob
import os
import re
import secrets
import sqlite3
import subprocess
from collections import defaultdict
from datetime import datetime

import pytest
import requests

DB_PATH = "/app/db/timeseries.sqlite3"
API_URL = "http://127.0.0.1:8000/data"
VALID_HEADERS = {"Authorization": "Bearer ops_token_99"}
INVALID_HEADERS = {"Authorization": "Bearer wrong_token"}


def api_get(sensor_id, headers=None):
    try:
        return requests.get(API_URL, params={"sensor_id": sensor_id}, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")


def source_expected_rows():
    text = subprocess.check_output(
        ["tesseract", "/app/config/specs.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    match = re.search(r"MULTIPLIER\s*=\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))", text)
    assert match, f"Could not extract MULTIPLIER from specs image; OCR output was {text!r}"
    multiplier = float(match.group(1))

    bins = defaultdict(list)
    csv_paths = sorted(glob.glob("/app/input/*.csv"))
    assert csv_paths, "No input CSV files found"
    for path in csv_paths:
        sensor_id = os.path.splitext(os.path.basename(path))[0]
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle)
            assert reader.fieldnames is not None and {"ts", "val"}.issubset(reader.fieldnames)
            for row in reader:
                stamp = datetime.fromisoformat(row["ts"].replace("Z", "+00:00"))
                hour = stamp.replace(minute=0, second=0, microsecond=0)
                if hour.tzinfo is not None:
                    hour = hour.replace(tzinfo=None)
                bins[(sensor_id, hour.isoformat())].append(float(row["val"]) * multiplier)

    return sorted(
        (sensor, hour, sum(values) / len(values))
        for (sensor, hour), values in bins.items()
    )


def test_sqlite_db_exists_and_data_correct():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_data';")
    assert cursor.fetchone() is not None, "Table 'hourly_data' does not exist in the database."

    # Check row count
    cursor.execute("SELECT COUNT(*) FROM hourly_data;")
    count = cursor.fetchone()[0]
    assert count == 3, f"Expected 3 rows in hourly_data, found {count}."

    # Check specific aggregated data
    cursor.execute("SELECT sensor_id, hour_ts, avg_val FROM hourly_data ORDER BY sensor_id, hour_ts;")
    rows = cursor.fetchall()

    expected_rows = [
        ("sensor_A", "2024-10-01T10:00:00", 38.5),
        ("sensor_A", "2024-10-01T11:00:00", 35.0),
        ("sensor_B", "2024-10-01T10:00:00", 77.0)
    ]

    for row in expected_rows:
        assert row in rows, f"Expected row {row} not found in database. Actual rows: {rows}"

    conn.close()


def test_database_matches_all_source_files_and_ocr_multiplier():
    expected = source_expected_rows()
    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute("PRAGMA table_info(hourly_data)").fetchall()
        columns = {row[1]: row[2].upper() for row in schema}
        assert columns.get("sensor_id") == "TEXT"
        assert columns.get("hour_ts") == "TEXT"
        assert columns.get("avg_val") == "REAL"
        actual = conn.execute(
            "SELECT sensor_id, hour_ts, avg_val FROM hourly_data ORDER BY sensor_id, hour_ts"
        ).fetchall()
    finally:
        conn.close()

    assert len(actual) == len(expected)
    for got, want in zip(actual, expected):
        assert got[:2] == want[:2]
        assert got[2] == pytest.approx(want[2], rel=1e-12, abs=1e-12)


def test_api_unauthorized():
    response = api_get("sensor_A", INVALID_HEADERS)
    assert response.status_code == 401, f"Expected HTTP 401 for invalid token, got {response.status_code}."


def test_api_rejects_every_non_exact_authorization_value():
    bad_headers = [
        None,
        {},
        {"Authorization": ""},
        {"Authorization": "ops_token_99"},
        {"Authorization": "Basic ops_token_99"},
        {"Authorization": "bearer ops_token_99"},
        {"Authorization": "Bearer ops_token_99 "},
        {"Authorization": "Bearer  ops_token_99"},
        {"Authorization": "Bearer " + secrets.token_hex(16)},
    ]
    for headers in bad_headers:
        response = api_get("sensor_A", headers)
        assert response.status_code == 401, (
            f"Expected HTTP 401 for Authorization headers {headers!r}, "
            f"got {response.status_code}."
        )


def test_api_sensor_a():
    response = api_get("sensor_A", VALID_HEADERS)
    assert response.status_code == 200, f"Expected HTTP 200 for sensor_A, got {response.status_code}."
    data = response.json()

    expected_data = [
        {"hour_ts": "2024-10-01T10:00:00", "avg_val": 38.5},
        {"hour_ts": "2024-10-01T11:00:00", "avg_val": 35.0}
    ]

    assert data == expected_data, f"API response for sensor_A did not match expected. Got: {data}"


def test_api_sensor_b():
    response = api_get("sensor_B", VALID_HEADERS)
    assert response.status_code == 200, f"Expected HTTP 200 for sensor_B, got {response.status_code}."
    data = response.json()

    expected_data = [
        {"hour_ts": "2024-10-01T10:00:00", "avg_val": 77.0}
    ]

    assert data == expected_data, f"API response for sensor_B did not match expected. Got: {data}"


def test_api_serves_random_database_rows_with_filtering_and_sorting():
    sensor_id = "sensor_probe_" + secrets.token_hex(12)
    other_sensor = "sensor_other_" + secrets.token_hex(12)
    rows = [
        (sensor_id, "2037-04-18T12:00:00", 91.25),
        (sensor_id, "2037-04-18T10:00:00", -7.5),
        (sensor_id, "2037-04-18T11:00:00", 13.75),
        (other_sensor, "2037-04-18T09:00:00", 999.0),
    ]
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany(
            "INSERT INTO hourly_data(sensor_id, hour_ts, avg_val) VALUES (?, ?, ?)", rows
        )
        conn.commit()
    finally:
        conn.close()

    response = api_get(sensor_id, VALID_HEADERS)
    assert response.status_code == 200
    assert response.json() == [
        {"hour_ts": "2037-04-18T10:00:00", "avg_val": -7.5},
        {"hour_ts": "2037-04-18T11:00:00", "avg_val": 13.75},
        {"hour_ts": "2037-04-18T12:00:00", "avg_val": 91.25},
    ]

    other_response = api_get(other_sensor, VALID_HEADERS)
    assert other_response.status_code == 200
    assert other_response.json() == [
        {"hour_ts": "2037-04-18T09:00:00", "avg_val": 999.0}
    ]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
