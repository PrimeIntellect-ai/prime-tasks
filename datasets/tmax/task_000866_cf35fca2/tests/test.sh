#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import sqlite3
import struct
import subprocess

import pytest

DB_PATH = "/home/user/features.db"
PROGRAM_PATH = "/home/user/process_data"
RAW_PATH = "/home/user/raw_sensors.bin"
RECORD = struct.Struct("<IQfI")


def calculate_expected():
    previous = {}
    deltas = {}

    with open(RAW_PATH, "rb") as raw:
        while True:
            data = raw.read(RECORD.size)
            if not data:
                break
            assert len(data) == RECORD.size, "Input contains a partial record"
            sensor_id, timestamp, value, checksum = RECORD.unpack(data)
            expected_checksum = sensor_id ^ (timestamp & 0xFFFFFFFF)
            if checksum != expected_checksum:
                continue

            if sensor_id in previous:
                deltas.setdefault(sensor_id, []).append(value - previous[sensor_id])
            previous[sensor_id] = value

    expected = {}
    for sensor_id, values in deltas.items():
        if len(values) < 2:
            continue
        n = len(values)
        mean = math.fsum(values) / n
        variance = math.fsum((value - mean) ** 2 for value in values) / (n - 1)
        std_dev = math.sqrt(variance)
        margin = 1.96 * std_dev / math.sqrt(n)
        lower = mean - margin
        upper = mean + margin
        expected[sensor_id] = (
            n,
            mean,
            lower,
            upper,
            int(lower > 0.0 or upper < 0.0),
        )
    return expected


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    assert os.path.exists(PROGRAM_PATH), f"Executable missing at {PROGRAM_PATH}"
    assert os.path.isfile(PROGRAM_PATH), f"Path {PROGRAM_PATH} is not a file"
    assert os.access(PROGRAM_PATH, os.X_OK), f"Program is not executable: {PROGRAM_PATH}"
    with open(PROGRAM_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "process_data must be a compiled executable"

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    result = subprocess.run(
        [PROGRAM_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"process_data exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_database_exists():
    """Check if the SQLite database was created."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"Path {DB_PATH} is not a file"


def test_table_schema_and_contents():
    """Check the schema and contents of the sensor_stats table."""
    assert os.path.exists(DB_PATH), "Database missing"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sensor_stats';")
    table = cursor.fetchone()
    assert table is not None, "Table 'sensor_stats' does not exist in the database."

    cursor.execute("PRAGMA table_info(sensor_stats)")
    schema = cursor.fetchall()
    assert len(schema) == 6, f"Expected 6 columns, found {len(schema)}"
    assert [(row[1], row[2].upper(), row[5]) for row in schema] == [
        ("sensor_id", "INTEGER", 1),
        ("n_deltas", "INTEGER", 0),
        ("mean_delta", "REAL", 0),
        ("ci_lower", "REAL", 0),
        ("ci_upper", "REAL", 0),
        ("is_drifting", "INTEGER", 0),
    ], f"Unexpected sensor_stats schema: {schema}"

    # Fetch all rows (retain the original checks).
    cursor.execute("SELECT sensor_id, n_deltas, is_drifting FROM sensor_stats ORDER BY sensor_id;")
    rows = cursor.fetchall()

    assert len(rows) == 10, f"Expected 10 rows in sensor_stats, found {len(rows)}"

    expected_drifting = {3, 7}

    for row in rows:
        sensor_id, n_deltas, is_drifting = row

        assert 900 <= n_deltas <= 1000, f"Sensor {sensor_id} has unexpected n_deltas: {n_deltas}"

        if sensor_id in expected_drifting:
            assert is_drifting == 1, f"Sensor {sensor_id} should be drifting (is_drifting=1), but got {is_drifting}"
        else:
            assert is_drifting == 0, f"Sensor {sensor_id} should NOT be drifting (is_drifting=0), but got {is_drifting}"

    expected = calculate_expected()
    cursor.execute(
        "SELECT sensor_id, n_deltas, mean_delta, ci_lower, ci_upper, is_drifting "
        "FROM sensor_stats ORDER BY sensor_id"
    )
    actual_rows = cursor.fetchall()

    assert [row[0] for row in actual_rows] == sorted(expected), (
        "Database has missing or unexpected sensor IDs"
    )

    for sensor_id, n_deltas, mean_delta, ci_lower, ci_upper, is_drifting in actual_rows:
        exp_n, exp_mean, exp_lower, exp_upper, exp_drifting = expected[sensor_id]
        assert n_deltas == exp_n, f"Sensor {sensor_id}: expected {exp_n} deltas, got {n_deltas}"
        assert mean_delta is not None and math.isfinite(mean_delta)
        assert ci_lower is not None and math.isfinite(ci_lower)
        assert ci_upper is not None and math.isfinite(ci_upper)
        assert math.isclose(mean_delta, exp_mean, rel_tol=1e-5, abs_tol=1e-5), (
            f"Sensor {sensor_id}: incorrect mean_delta"
        )
        assert math.isclose(ci_lower, exp_lower, rel_tol=1e-5, abs_tol=1e-5), (
            f"Sensor {sensor_id}: incorrect ci_lower"
        )
        assert math.isclose(ci_upper, exp_upper, rel_tol=1e-5, abs_tol=1e-5), (
            f"Sensor {sensor_id}: incorrect ci_upper"
        )
        assert is_drifting == exp_drifting, f"Sensor {sensor_id}: incorrect drift classification"

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
