#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE=/app/detect_outliers
REAL_ORACLE=/app/detect_outliers.verifier-real
WRAPPER_LOG=/tmp/detect_outliers_invocations.jsonl

cleanup() {
    rm -f "$ORACLE"
    if [ -e "$REAL_ORACLE" ]; then
        mv "$REAL_ORACLE" "$ORACLE"
        chmod +x "$ORACLE"
    fi
}
trap cleanup EXIT

rm -f "$REAL_ORACLE" "$WRAPPER_LOG"
mv "$ORACLE" "$REAL_ORACLE"

cat << 'WRAPPER_EOF' > "$ORACLE"
#!/usr/bin/env python3
import base64
import json
import os
import subprocess
import sys
import time
import uuid

real_oracle = "/app/detect_outliers.verifier-real"
log_path = "/tmp/detect_outliers_invocations.jsonl"
payload = sys.stdin.buffer.read()
invocation_id = uuid.uuid4().hex

def log_event(event):
    record = {
        "event": event,
        "id": invocation_id,
        "pid": os.getpid(),
        "time_ns": time.time_ns(),
    }
    if event == "start":
        record["input_b64"] = base64.b64encode(payload).decode("ascii")
    data = (json.dumps(record, separators=(",", ":")) + "\n").encode()
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)

log_event("start")
time.sleep(0.5)
proc = subprocess.run([real_oracle], input=payload, stdout=subprocess.PIPE,
                      stderr=subprocess.PIPE)
log_event("end")
sys.stdout.buffer.write(proc.stdout)
sys.stderr.buffer.write(proc.stderr)
sys.exit(proc.returncode)
WRAPPER_EOF
chmod 755 "$ORACLE"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import sqlite3
import string
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:8000/process"
REAL_ORACLE = "/app/detect_outliers.verifier-real"
WRAPPER_LOG = "/tmp/detect_outliers_invocations.jsonl"


def post_database(db_path, timeout=30):
    try:
        response = requests.post(URL, json={"db_path": db_path}, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service or request timed out: {e}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "success", (
        f"Expected status 'success', got {data.get('status')}"
    )
    return data


def test_01_process_endpoint_and_anomalies():
    db_path = '/tmp/test_data.sqlite'

    assert os.path.exists(db_path), f"Database {db_path} does not exist."

    # Read original data to compute expected anomalies
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM wide_readings ORDER BY timestamp ASC")
    rows = cursor.fetchall()

    # Get column names
    col_names = [description[0] for description in cursor.description]
    ts_idx = col_names.index('timestamp')

    expected_anomalies = []

    # For each sensor column
    for col_idx, col_name in enumerate(col_names):
        if col_name == 'timestamp':
            continue

        prev_val = None
        for row in rows:
            ts = row[ts_idx]
            val = row[col_idx]

            if val is None:
                continue

            if prev_val is None:
                diff = 0.0
            else:
                diff = val - prev_val

            if abs(diff) > 15.0:
                expected_anomalies.append((ts, col_name, diff))

            prev_val = val

    data = post_database(db_path, timeout=20)

    # Check database for anomalies table
    try:
        cursor.execute("SELECT timestamp, sensor_id, diff_value FROM anomalies ORDER BY sensor_id, timestamp")
        actual_anomalies = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'anomalies' table: {e}")

    assert len(actual_anomalies) == len(expected_anomalies), f"Expected {len(expected_anomalies)} rows in anomalies table, got {len(actual_anomalies)}"
    assert data.get("anomalies_inserted") == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies inserted in response, got {data.get('anomalies_inserted')}"

    # Sort both lists to compare
    expected_anomalies.sort(key=lambda x: (x[1], x[0]))
    actual_anomalies.sort(key=lambda x: (x[1], x[0]))

    for exp, act in zip(expected_anomalies, actual_anomalies):
        assert exp[0] == act[0], f"Timestamp mismatch: expected {exp[0]}, got {act[0]}"
        assert exp[1] == act[1], f"Sensor ID mismatch: expected {exp[1]}, got {act[1]}"
        assert abs(exp[2] - act[2]) < 1e-4, f"Diff value mismatch: expected {exp[2]}, got {act[2]}"

    conn.close()


def oracle_predictions(diffs):
    payload = "".join(f"{value:.17g}\n" for value in diffs).encode()
    result = subprocess.run(
        [REAL_ORACLE], input=payload, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, check=True
    )
    output = result.stdout.decode().splitlines()
    assert len(output) == len(diffs), "Oracle returned an unexpected prediction count"
    assert all(value in ("0", "1") for value in output)
    return [int(value) for value in output]


def test_02_random_database_oracle_invocation_and_parallelism():
    rng = random.SystemRandom()
    token = ''.join(rng.choice(string.ascii_lowercase) for _ in range(10))
    db_path = f"/tmp/random_pipeline_{token}.sqlite"
    sensor_names = [f"probe_{token}_{i}" for i in range(6)]
    timestamps = sorted(rng.sample(range(10000, 90000), 15))

    # Build values in timestamp order, with unpredictable normal changes, large
    # changes, and NULLs. Rows are inserted out of timestamp order.
    values_by_sensor = {}
    for sensor_index, sensor in enumerate(sensor_names):
        current = rng.uniform(-25.0, 25.0)
        values = []
        for i in range(len(timestamps)):
            if i > 0:
                if i in (3, 10):
                    magnitude = rng.uniform(18.0, 42.0)
                    current += magnitude if (sensor_index + i) % 2 else -magnitude
                else:
                    current += rng.uniform(-4.0, 4.0)
            values.append(current)
        values[6 + (sensor_index % 2)] = None
        values_by_sensor[sensor] = values

    conn = sqlite3.connect(db_path)
    quoted_columns = ", ".join(f'"{name}" REAL' for name in sensor_names)
    conn.execute(f'CREATE TABLE wide_readings (timestamp INTEGER, {quoted_columns})')
    row_indices = list(range(len(timestamps)))
    rng.shuffle(row_indices)
    placeholders = ",".join("?" for _ in range(1 + len(sensor_names)))
    for i in row_indices:
        row = [timestamps[i]] + [values_by_sensor[name][i] for name in sensor_names]
        conn.execute(f"INSERT INTO wide_readings VALUES ({placeholders})", row)
    conn.commit()
    conn.close()
    os.chmod(db_path, 0o666)

    expected = []
    expected_diff_streams = []
    for sensor in sensor_names:
        previous = None
        diffs = []
        diff_rows = []
        for timestamp, value in zip(timestamps, values_by_sensor[sensor]):
            if value is None:
                continue
            diff = 0.0 if previous is None else value - previous
            diffs.append(diff)
            diff_rows.append((timestamp, sensor, diff))
            previous = value
        expected_diff_streams.append(diffs)
        predictions = oracle_predictions(diffs)
        expected.extend(row for row, prediction in zip(diff_rows, predictions) if prediction == 1)

    try:
        os.unlink(WRAPPER_LOG)
    except FileNotFoundError:
        pass

    data = post_database(db_path)

    conn = sqlite3.connect(db_path)
    try:
        actual = conn.execute(
            "SELECT timestamp, sensor_id, diff_value FROM anomalies "
            "ORDER BY sensor_id, timestamp"
        ).fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'anomalies' table in randomized database: {e}")
    finally:
        conn.close()

    expected.sort(key=lambda row: (row[1], row[0]))
    actual.sort(key=lambda row: (row[1], row[0]))
    assert data.get("anomalies_inserted") == len(expected)
    assert len(actual) == len(expected)
    for exp, act in zip(expected, actual):
        assert exp[0] == act[0]
        assert exp[1] == act[1]
        assert abs(exp[2] - act[2]) < 1e-4

    assert os.path.exists(WRAPPER_LOG), "Service did not invoke /app/detect_outliers"
    with open(WRAPPER_LOG, encoding="utf-8") as handle:
        events = [json.loads(line) for line in handle if line.strip()]

    starts = {event["id"]: event for event in events if event["event"] == "start"}
    ends = {event["id"]: event for event in events if event["event"] == "end"}
    assert len(starts) == len(sensor_names), (
        "The oracle must be invoked once for each unique sensor"
    )
    assert set(starts) == set(ends), "One or more oracle invocations did not finish"

    observed_streams = []
    for event in starts.values():
        raw = base64.b64decode(event["input_b64"])
        observed_streams.append([float(line) for line in raw.decode().splitlines()])

    unmatched = list(observed_streams)
    for expected_stream in expected_diff_streams:
        match_index = None
        for index, observed in enumerate(unmatched):
            if len(observed) == len(expected_stream) and all(
                abs(a - b) < 1e-8 for a, b in zip(observed, expected_stream)
            ):
                match_index = index
                break
        assert match_index is not None, (
            "Oracle inputs were not the per-sensor first differences"
        )
        unmatched.pop(match_index)
    assert not unmatched

    intervals = sorted(
        (starts[key]["time_ns"], ends[key]["time_ns"]) for key in starts
    )
    active_ends = []
    max_concurrent = 0
    for start, end in intervals:
        active_ends = [active_end for active_end in active_ends if active_end > start]
        active_ends.append(end)
        max_concurrent = max(max_concurrent, len(active_ends))
    assert max_concurrent >= 2, "Sensor oracle invocations were not processed in parallel"

    os.unlink(db_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
