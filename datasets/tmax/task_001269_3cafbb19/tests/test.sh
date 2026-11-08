#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import statistics
import subprocess
from datetime import datetime, timezone
import pytest

SCRIPT_PATH = "/home/user/investigate.py"
UNIFIED_LOGS_PATH = "/home/user/unified_logs.txt"
REPORT_PATH = "/home/user/report.json"
DB_PATH = "/home/user/data/sensors.db"
LOGS_DIR = "/home/user/logs"


def expected_unified_lines():
    entries = []

    with open(os.path.join(LOGS_DIR, "gateway.log"), "r") as f:
        for raw in f:
            timestamp, message = raw.rstrip("\n").split(maxsplit=1)
            dt = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
            entries.append((dt, f"[{dt.strftime('%Y-%m-%dT%H:%M:%SZ')}] [gateway.log] {message}"))

    with open(os.path.join(LOGS_DIR, "aggregator.log"), "r") as f:
        for raw in f:
            timestamp, message = raw.rstrip("\n").split(maxsplit=1)
            dt = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            entries.append((dt, f"[{dt.strftime('%Y-%m-%dT%H:%M:%SZ')}] [aggregator.log] {message}"))

    with open(os.path.join(LOGS_DIR, "db_writer.log"), "r") as f:
        for raw in f:
            date_part, time_part, message = raw.rstrip("\n").split(maxsplit=2)
            dt = datetime.strptime(f"{date_part} {time_part}", "%Y/%m/%d %H:%M:%S").replace(tzinfo=timezone.utc)
            entries.append((dt, f"[{dt.strftime('%Y-%m-%dT%H:%M:%SZ')}] [db_writer.log] {message}"))

    entries.sort(key=lambda item: item[0])
    return [line for _, line in entries]


def database_truth():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT sensor_id, value FROM readings").fetchall()
    finally:
        conn.close()

    sensor_values = {}
    for sensor_id, value in rows:
        sensor_values.setdefault(sensor_id, []).append(value)
    stddevs = {s: statistics.stdev(vals) for s, vals in sensor_values.items() if len(vals) > 1}
    sensor = max(stddevs, key=stddevs.get)
    return sensor, round(stddevs[sensor], 2)


@pytest.fixture(scope="session", autouse=True)
def run_investigation():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing or is not a regular file."

    expected_logs = expected_unified_lines()
    expected_sensor, expected_stddev = database_truth()

    for output in (UNIFIED_LOGS_PATH, REPORT_PATH):
        if os.path.lexists(output):
            os.remove(output)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return expected_logs, expected_sensor, expected_stddev


def test_unified_logs_exists_and_sorted(run_investigation):
    expected_logs, _, _ = run_investigation
    unified_logs_path = UNIFIED_LOGS_PATH
    assert os.path.exists(unified_logs_path), f"{unified_logs_path} is missing."

    with open(unified_logs_path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, f"{unified_logs_path} is empty."

    timestamps = []
    for line in lines:
        parts = line.split("]", 1)
        assert len(parts) == 2, f"Line format incorrect, missing ']': {line.strip()}"
        assert parts[0].startswith("["), f"Line format incorrect, missing '[': {line.strip()}"

        ts_str = parts[0][1:]
        assert len(ts_str) == 20 and ts_str.endswith("Z"), f"Timestamp not in correct ISO8601 format: {ts_str}"
        timestamps.append(ts_str)

    assert timestamps == sorted(timestamps), "The entries in unified_logs.txt are not sorted chronologically."
    assert "FATAL" in lines[-1], "The last log entry does not contain 'FATAL'."
    assert "2023-10-25T13:22:05Z" in lines[-1], "The last log entry does not have the correct crash timestamp."

    actual_logs = [line.rstrip("\n") for line in lines]
    assert actual_logs == expected_logs, (
        "unified_logs.txt must contain every source entry exactly once, with the source filename, "
        "message, normalized timestamp, and chronological ordering preserved."
    )


def test_report_json_exists_and_correct(run_investigation):
    _, snapshotted_sensor, snapshotted_stddev = run_investigation
    report_path = REPORT_PATH
    assert os.path.exists(report_path), f"{report_path} is missing."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not a valid JSON file.")

    assert "crash_time" in data, "Key 'crash_time' missing in report.json"
    assert "anomalous_sensor" in data, "Key 'anomalous_sensor' missing in report.json"
    assert "highest_stddev" in data, "Key 'highest_stddev' missing in report.json"
    assert set(data.keys()) == {"crash_time", "anomalous_sensor", "highest_stddev"}, \
        "report.json must contain exactly the three required keys."

    assert data["crash_time"] == "2023-10-25T13:22:05Z", f"Incorrect crash_time: {data['crash_time']}"

    db_path = DB_PATH
    assert os.path.exists(db_path), f"Database {db_path} is missing."
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT sensor_id, value FROM readings")
    rows = cursor.fetchall()
    conn.close()

    sensor_values = {}
    for sensor_id, value in rows:
        sensor_values.setdefault(sensor_id, []).append(value)

    stddevs = {s: statistics.stdev(vals) for s, vals in sensor_values.items() if len(vals) > 1}
    expected_anomalous_sensor = max(stddevs, key=stddevs.get)
    expected_highest_stddev = round(stddevs[expected_anomalous_sensor], 2)

    assert data["anomalous_sensor"] == expected_anomalous_sensor, f"Incorrect anomalous_sensor: {data['anomalous_sensor']}"
    assert data["anomalous_sensor"] == snapshotted_sensor, f"Incorrect anomalous_sensor: {data['anomalous_sensor']}"

    reported_stddev = data["highest_stddev"]
    assert isinstance(reported_stddev, (int, float)), "highest_stddev must be a float."
    assert type(reported_stddev) is float, "highest_stddev must be a float."
    assert abs(reported_stddev - expected_highest_stddev) <= 0.1, f"Incorrect highest_stddev: expected approx {expected_highest_stddev}, got {reported_stddev}"
    assert abs(reported_stddev - snapshotted_stddev) <= 0.1, f"Incorrect highest_stddev: expected approx {snapshotted_stddev}, got {reported_stddev}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
