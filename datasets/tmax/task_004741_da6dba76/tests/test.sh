#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import sqlite3
import subprocess
from collections import defaultdict
from datetime import datetime

import pytest

DB_PATH = "/home/user/fleet_data.db"
CRON_PATH = "/home/user/cron_schedule.txt"
SCRIPT_PATH = "/home/user/etl_pipeline.py"
RAW_PATH = "/home/user/raw_data/measurements.jsonl"


def test_database_exists():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} was not created."
    assert os.path.isfile(DB_PATH), f"Path {DB_PATH} is not a file."


def test_hourly_stats_table_and_data():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_stats';")
        assert cursor.fetchone() is not None, "Table 'hourly_stats' does not exist in the database."

        cursor.execute("SELECT bucket, vehicle_id, avg_speed, max_temp FROM hourly_stats ORDER BY vehicle_id, bucket;")
        rows = cursor.fetchall()
        expected_rows = [
            ("2023-10-01 10:00:00", "V1", 50.0, 22.0),
            ("2023-10-01 11:00:00", "V1", 60.0, 26.0),
            ("2023-10-01 10:00:00", "V2", 35.0, 19.0),
        ]

        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."
        for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
            assert actual[0] == expected[0], f"Row {i+1} bucket mismatch: expected {expected[0]}, got {actual[0]}"
            assert actual[1] == expected[1], f"Row {i+1} vehicle_id mismatch: expected {expected[1]}, got {actual[1]}"
            assert abs(actual[2] - expected[2]) < 1e-5, f"Row {i+1} avg_speed mismatch: expected {expected[2]}, got {actual[2]}"
            assert abs(actual[3] - expected[3]) < 1e-5, f"Row {i+1} max_temp mismatch: expected {expected[3]}, got {actual[3]}"
    except sqlite3.Error as exc:
        pytest.fail(f"SQLite error occurred: {exc}")
    finally:
        if conn is not None:
            conn.close()


def test_cron_schedule_file():
    assert os.path.exists(CRON_PATH), f"Cron schedule file {CRON_PATH} was not created."
    assert os.path.isfile(CRON_PATH), f"Path {CRON_PATH} is not a file."

    with open(CRON_PATH, "r") as handle:
        content = handle.read().strip()
    assert content, f"File {CRON_PATH} is empty."

    pattern = r"^0\s+\*\s+\*\s+\*\s+\*\s+(?:/usr/bin/)?python3\s+/home/user/etl_pipeline\.py$"
    match_found = any(re.match(pattern, line.strip()) for line in content.splitlines())
    assert match_found, (
        f"File {CRON_PATH} does not contain the correct cron schedule. "
        f"Expected a line matching '0 * * * * python3 /home/user/etl_pipeline.py'. "
        f"Actual content: {content}"
    )


def derive_expected(raw_lines):
    unique_lines = []
    seen = set()
    for line in raw_lines:
        if line not in seen:
            seen.add(line)
            unique_lines.append(line)

    by_vehicle = defaultdict(list)
    for line in unique_lines:
        record = json.loads(line)
        record["_dt"] = datetime.fromisoformat(record["ts"])
        by_vehicle[record["vehicle_id"]].append(record)

    cleaned = []
    for records in by_vehicle.values():
        records.sort(key=lambda record: record["_dt"])
        for index, record in enumerate(records):
            if record["speed"] is None:
                previous = next((records[j] for j in range(index - 1, -1, -1) if records[j]["speed"] is not None), None)
                following = next((records[j] for j in range(index + 1, len(records)) if records[j]["speed"] is not None), None)
                assert previous is not None and following is not None
                elapsed = (record["_dt"] - previous["_dt"]).total_seconds()
                span = (following["_dt"] - previous["_dt"]).total_seconds()
                record["speed"] = previous["speed"] + (following["speed"] - previous["speed"]) * elapsed / span
        cleaned.extend(records)

    groups = {}
    for record in cleaned:
        bucket = record["_dt"].replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%d %H:%M:%S")
        key = (bucket, record["vehicle_id"])
        if key not in groups:
            groups[key] = {"speeds": [], "temps": []}
        groups[key]["speeds"].append(float(record["speed"]))
        groups[key]["temps"].append(float(record["temp"]))

    return sorted(
        (bucket, vehicle, sum(values["speeds"]) / len(values["speeds"]), max(values["temps"]))
        for (bucket, vehicle), values in groups.items()
    )


def read_result():
    assert os.path.isfile(DB_PATH), "Executing the ETL script did not create the database."
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_stats'")
        assert cursor.fetchone() is not None, "Executing the ETL script did not create hourly_stats."
        cursor.execute("PRAGMA table_info(hourly_stats)")
        columns = [(row[1], row[2].upper()) for row in cursor.fetchall()]
        assert columns == [
            ("bucket", "TEXT"),
            ("vehicle_id", "TEXT"),
            ("avg_speed", "REAL"),
            ("max_temp", "REAL"),
        ], f"Unexpected hourly_stats schema: {columns}"
        cursor.execute("SELECT bucket, vehicle_id, avg_speed, max_temp FROM hourly_stats ORDER BY bucket, vehicle_id")
        return cursor.fetchall()


def assert_rows(actual, expected):
    assert len(actual) == len(expected), f"Expected {len(expected)} rows after execution, got {len(actual)}: {actual}"
    for actual_row, expected_row in zip(actual, expected):
        assert actual_row[0] == expected_row[0]
        assert actual_row[1] == expected_row[1]
        assert math.isclose(float(actual_row[2]), expected_row[2], rel_tol=1e-9, abs_tol=1e-7)
        assert math.isclose(float(actual_row[3]), expected_row[3], rel_tol=1e-9, abs_tol=1e-7)


def test_zz_script_executes_dynamic_etl_and_is_idempotent():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."

    rng = random.SystemRandom()
    speed_a = float(rng.randint(113, 413))
    speed_b = float(rng.randint(517, 817))
    temp_a = float(rng.randint(31, 61))
    temp_b = float(rng.randint(71, 101))

    records = [
        {"ts": "2041-06-17T09:05:00", "vehicle_id": "DYNAMIC-A", "speed": speed_a, "temp": temp_a},
        {"ts": "2041-06-17T09:17:00", "vehicle_id": "DYNAMIC-A", "speed": None, "temp": temp_a + 40},
        {"ts": "2041-06-17T09:41:00", "vehicle_id": "DYNAMIC-A", "speed": speed_a + 36, "temp": temp_a + 2},
        {"ts": "2041-06-17T09:52:00", "vehicle_id": "DYNAMIC-A", "speed": speed_a + 80, "temp": temp_a + 3},
        {"ts": "2041-06-17T10:50:00", "vehicle_id": "DYNAMIC-B", "speed": speed_b, "temp": temp_b},
        {"ts": "2041-06-17T11:14:00", "vehicle_id": "DYNAMIC-B", "speed": None, "temp": temp_b + 9},
        {"ts": "2041-06-17T11:50:00", "vehicle_id": "DYNAMIC-B", "speed": speed_b + 66, "temp": temp_b + 4},
    ]
    lines = [json.dumps(record, separators=(",", ":")) for record in records]
    lines.append(lines[3])  # exact duplicate: must be removed
    lines.append(json.dumps(records[3], separators=(", ", ": ")))  # same JSON, different raw line: must remain
    rng.shuffle(lines)

    os.makedirs(os.path.dirname(RAW_PATH), exist_ok=True)
    with open(RAW_PATH, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    expected = derive_expected(lines)

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    for run_number in (1, 2):
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"ETL script failed on run {run_number} with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert_rows(read_result(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
