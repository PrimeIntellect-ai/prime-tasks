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
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import sqlite3
import subprocess
import tempfile

import pytest
import requests
from PIL import Image

RAW_LOGS = "/app/raw_logs.csv"
VIDEO = "/app/server_dashboard.mp4"
CLEANED_CSV = "/home/user/cleaned_logs.csv"
DATABASE = "/home/user/logs.db"
HEADERS = ["timestamp", "ip_address", "response_time", "cpu_load", "rolling_resp", "alert"]


def valid_ipv4(value):
    if not re.fullmatch(r"(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}", value):
        return False
    return all(0 <= int(part) <= 255 for part in value.split("."))


def derive_alerts():
    assert os.path.isfile(VIDEO), f"Input video missing: {VIDEO}"
    with tempfile.TemporaryDirectory() as directory:
        pattern = os.path.join(directory, "frame_%03d.png")
        subprocess.run(
            ["ffmpeg", "-v", "error", "-i", VIDEO, "-vf", "fps=1", pattern],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        frames = sorted(
            os.path.join(directory, name)
            for name in os.listdir(directory)
            if name.endswith(".png")
        )
        assert len(frames) == 10, f"Expected 10 one-fps frames, decoded {len(frames)}"
        result = {}
        for second, path in enumerate(frames):
            with Image.open(path) as image:
                gray = image.convert("L")
                pixels = list(gray.getdata())
                average = sum(pixels) / len(pixels)
            result[second] = 1 if average > 128 else 0
        return result


def derive_expected_rows():
    alerts = derive_alerts()
    with open(RAW_LOGS, newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["timestamp", "ip_address", "response_time", "cpu_load"]
        source_rows = list(reader)

    cleaned = []
    previous_cpu = 0.0
    responses = []
    for source in source_rows:
        if not valid_ipv4(source["ip_address"]):
            continue

        timestamp = int(source["timestamp"])
        response_time = float(source["response_time"])
        cpu_text = source["cpu_load"].strip()
        if cpu_text:
            previous_cpu = float(cpu_text)
        cpu_load = previous_cpu

        responses.append(response_time)
        rolling_resp = sum(responses[-3:]) / len(responses[-3:])
        cleaned.append({
            "timestamp": timestamp,
            "ip_address": source["ip_address"],
            "response_time": response_time,
            "cpu_load": cpu_load,
            "rolling_resp": rolling_resp,
            "alert": alerts[timestamp],
        })
    return cleaned


@pytest.fixture(scope="session")
def expected_rows():
    return derive_expected_rows()


def assert_numeric(actual, expected, field):
    try:
        value = float(actual)
    except (TypeError, ValueError):
        pytest.fail(f"{field} is not numeric: {actual!r}")
    tolerance = 0.0051 if field == "rolling_resp" else 1e-9
    assert math.isclose(value, float(expected), rel_tol=0.0, abs_tol=tolerance), (
        f"Unexpected {field}: expected {expected}, got {actual}"
    )


def assert_complete_row(actual, expected):
    assert int(actual["timestamp"]) == expected["timestamp"]
    assert actual["ip_address"] == expected["ip_address"]
    assert_numeric(actual["response_time"], expected["response_time"], "response_time")
    assert_numeric(actual["cpu_load"], expected["cpu_load"], "cpu_load")
    assert_numeric(actual["rolling_resp"], expected["rolling_resp"], "rolling_resp")
    assert int(actual["alert"]) == expected["alert"]


def test_cleaned_logs_csv(expected_rows):
    assert os.path.isfile(CLEANED_CSV), f"Cleaned logs file missing: {CLEANED_CSV}"
    with open(CLEANED_CSV, newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames is not None, "CSV is empty or missing headers"
        for header in HEADERS:
            assert header in reader.fieldnames, f"Missing header '{header}' in cleaned_logs.csv"
        assert reader.fieldnames == HEADERS, f"Unexpected CSV headers: {reader.fieldnames}"
        rows = list(reader)

    assert len(rows) == 8, f"Expected 8 valid rows, found {len(rows)}"
    assert len(rows) == len(expected_rows)
    timestamps = [int(row["timestamp"]) for row in rows]
    expected_timestamps = [row["timestamp"] for row in expected_rows]
    assert timestamps == expected_timestamps, f"Unexpected timestamps in CSV: {timestamps}"
    for actual, expected in zip(rows, expected_rows):
        assert_complete_row(actual, expected)


def test_sqlite_database(expected_rows):
    assert os.path.isfile(DATABASE), f"Database file missing: {DATABASE}"
    conn = sqlite3.connect(DATABASE)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='metrics'")
        assert cursor.fetchone(), "Table 'metrics' missing in logs.db"

        cursor.execute("PRAGMA table_info(metrics)")
        columns = [row[1] for row in cursor.fetchall()]
        for header in HEADERS:
            assert header in columns, f"Column '{header}' missing from metrics"

        cursor.execute(
            "SELECT timestamp, ip_address, response_time, cpu_load, rolling_resp, alert "
            "FROM metrics ORDER BY CAST(timestamp AS INTEGER)"
        )
        records = cursor.fetchall()
    finally:
        conn.close()

    assert len(records) == 8, f"Expected 8 rows in metrics table, found {len(records)}"
    actual_rows = [dict(zip(HEADERS, record)) for record in records]
    alerts = [int(row["timestamp"]) for row in actual_rows if int(row["alert"]) == 1]
    expected_alerts = [row["timestamp"] for row in expected_rows if row["alert"] == 1]
    assert alerts == expected_alerts, f"Expected alerts at timestamps {expected_alerts}, found {alerts}"
    for actual, expected in zip(actual_rows, expected_rows):
        assert_complete_row(actual, expected)


def test_api_alerts(expected_rows):
    url = "http://127.0.0.1:8000/alerts"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {url}: {exc}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")
    assert isinstance(data, list), "Expected a JSON array for /alerts"
    assert all(isinstance(value, int) and not isinstance(value, bool) for value in data)
    expected = [row["timestamp"] for row in expected_rows if row["alert"] == 1]
    assert sorted(data) == expected, f"Expected alerts {expected}, got {data}"


def test_api_stats(expected_rows):
    url = "http://127.0.0.1:8000/stats"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {url}: {exc}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")
    assert isinstance(data, dict), "Expected a JSON object for /stats"

    expected_stats = {
        str(row["timestamp"]): round(row["rolling_resp"], 2)
        for row in expected_rows
    }
    assert set(data) == set(expected_stats), (
        f"Unexpected /stats timestamp keys: expected {sorted(expected_stats)}, got {sorted(data)}"
    )
    for timestamp, expected_value in expected_stats.items():
        try:
            value = float(data[timestamp])
        except (TypeError, ValueError):
            pytest.fail(f"rolling_resp for {timestamp} is not numeric: {data[timestamp]!r}")
        assert math.isclose(value, expected_value, rel_tol=0.0, abs_tol=1e-9), (
            f"Expected rolling_resp for {timestamp} to be {expected_value}, got {data[timestamp]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
