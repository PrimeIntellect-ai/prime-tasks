#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import sqlite3
import subprocess
import pytest
from collections import defaultdict

DB_PATH = "/home/user/metrics.db"
CSV_PATH = "/home/user/raw_telemetry.csv"
PIPELINE_PATH = "/home/user/pipeline.sh"


def get_expected_aggregates():
    if not os.path.exists(CSV_PATH):
        pytest.fail(f"Input file {CSV_PATH} is missing. Cannot compute expected state.")

    aggregates = defaultdict(list)
    with open(CSV_PATH, 'r') as f:
        for line in f:
            # Strip newline exactly as read
            line = line.strip('\n')
            fields = line.split(',')

            # Quality Gate: strictly 4 comma-separated fields
            if len(fields) == 4:
                try:
                    ts = int(fields[0])
                    sensor_id = fields[1]
                    value = float(fields[2])

                    # Time-based Bucketing
                    bucket = (ts // 3600) * 3600
                    aggregates[(bucket, sensor_id)].append(value)
                except ValueError:
                    # Ignore rows where types don't match expectations
                    continue

    expected = []
    for (bucket, sensor_id), values in aggregates.items():
        avg = sum(values) / len(values)
        # Round to exactly 2 decimal places
        expected.append((bucket, sensor_id, round(avg, 2)))

    return sorted(expected)


def read_actual_aggregates():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created by the pipeline."
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT bucket_time, sensor_id, avg_value "
            "FROM hourly_aggregates ORDER BY bucket_time ASC, sensor_id ASC;"
        ).fetchall()
    finally:
        conn.close()
    return [(row[0], row[1], round(float(row[2]), 2)) for row in rows]


def test_00_pipeline_exists_and_produces_database_from_input():
    assert os.path.isfile(PIPELINE_PATH), f"Required Bash pipeline {PIPELINE_PATH} is missing."

    syntax = subprocess.run(
        ["bash", "-n", PIPELINE_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert syntax.returncode == 0, f"pipeline.sh is not valid Bash syntax:\n{syntax.stderr}"

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    base = ((1700000000 + secrets.randbelow(1000000)) // 3600) * 3600
    sensor_a = "A_" + secrets.token_hex(5)
    sensor_b = "B_" + secrets.token_hex(5)
    v1 = 10 + secrets.randbelow(500) / 10.0
    v2 = 60 + secrets.randbelow(500) / 10.0
    v3 = 120 + secrets.randbelow(500) / 10.0
    dynamic_csv = (
        f"{base + 17},{sensor_a},{v1},ok\n"
        f"{base + 901},{sensor_a},{v2},also_ok\n"
        f"{base + 1800},{sensor_b},{v3},ok\n"
        f"{base + 3700},{sensor_a},{v3},next_hour\n"
        f"{base + 100},{sensor_b},999,bad,extra,column\n"
        f"{base + 200},{sensor_b},888,embedded\n"
        "continuation\n"
        f"not-a-timestamp,{sensor_b},12.3,invalid\n"
    )

    restore_result = None
    try:
        with open(CSV_PATH, "w") as f:
            f.write(dynamic_csv)
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)

        result = subprocess.run(
            ["bash", PIPELINE_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Running pipeline.sh failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        expected = get_expected_aggregates()
        actual = read_actual_aggregates()
        assert actual == expected, (
            "Running pipeline.sh on a fresh input did not produce the expected database.\n"
            f"Expected: {expected}\nGot:      {actual}"
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        restore_result = subprocess.run(
            ["bash", PIPELINE_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )

    assert restore_result.returncode == 0, (
        "pipeline.sh failed when rebuilding metrics.db from the required input.\n"
        f"stdout:\n{restore_result.stdout}\nstderr:\n{restore_result.stderr}"
    )


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created."


def test_table_schema():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(hourly_aggregates);")
    columns = cursor.fetchall()
    conn.close()

    assert len(columns) > 0, "Table 'hourly_aggregates' does not exist in the database."

    col_dict = {col[1]: col[2].upper() for col in columns}

    assert "bucket_time" in col_dict, "Column 'bucket_time' is missing."
    assert "INTEGER" in col_dict["bucket_time"], f"Column 'bucket_time' must be INTEGER, got {col_dict['bucket_time']}."

    assert "sensor_id" in col_dict, "Column 'sensor_id' is missing."
    assert "TEXT" in col_dict["sensor_id"], f"Column 'sensor_id' must be TEXT, got {col_dict['sensor_id']}."

    assert "avg_value" in col_dict, "Column 'avg_value' is missing."
    assert "REAL" in col_dict["avg_value"], f"Column 'avg_value' must be REAL, got {col_dict['avg_value']}."


def test_aggregated_data_correctness():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    expected_data = get_expected_aggregates()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT bucket_time, sensor_id, avg_value FROM hourly_aggregates ORDER BY bucket_time ASC, sensor_id ASC;")
        actual_data = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'hourly_aggregates' table: {e}")
    finally:
        conn.close()

    # Ensure precision issues don't fail the test if they inserted correctly but sqlite returned float
    actual_data_rounded = [(row[0], row[1], round(float(row[2]), 2)) for row in actual_data]

    assert actual_data_rounded == expected_data, (
        f"Aggregated data mismatch.\n"
        f"Expected: {expected_data}\n"
        f"Got:      {actual_data_rounded}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
