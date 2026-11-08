#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

EXTRACTOR = '/home/user/extractor.go'
OUTPUT = '/home/user/anomalies.jsonl'
DATABASE = '/home/user/datasets/sensors.db'
BINARY = '/tmp/extractor_under_test'

ORIGINAL_EXPECTED = [
    {"sensor_id": "SENS-01", "reading_time": "2023-10-01T15:00:00Z", "temperature": 26.5},
    {"sensor_id": "SENS-02", "reading_time": "2023-10-01T14:00:00Z", "temperature": 21.0},
    {"sensor_id": "SENS-01", "reading_time": "2023-10-01T12:00:00Z", "temperature": 25.4},
    {"sensor_id": "SENS-02", "reading_time": "2023-10-01T11:00:00Z", "temperature": 22.1},
]


def read_jsonl(path):
    assert os.path.isfile(path), f"The output file {path} is missing."
    with open(path, 'r', encoding='utf-8') as f:
        lines = [line for line in f.read().strip().split('\n') if line.strip()]

    parsed = []
    for i, line in enumerate(lines):
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i + 1} in anomalies.jsonl is not valid JSON: {line}")
    return parsed


def assert_original_content(actual):
    assert len(actual) == 4, f"Expected exactly 4 lines in anomalies.jsonl, but found {len(actual)}."
    for i, (row, expected) in enumerate(zip(actual, ORIGINAL_EXPECTED)):
        assert "sensor_id" in row, f"Line {i + 1} missing 'sensor_id' key."
        assert "reading_time" in row, f"Line {i + 1} missing 'reading_time' key."
        assert "temperature" in row, f"Line {i + 1} missing 'temperature' key."
        assert row["sensor_id"] == expected["sensor_id"], f"Line {i + 1} sensor_id mismatch: expected {expected['sensor_id']}, got {row['sensor_id']}."
        assert row["reading_time"] == expected["reading_time"], f"Line {i + 1} reading_time mismatch: expected {expected['reading_time']}, got {row['reading_time']}."
        assert float(row["temperature"]) == expected["temperature"], f"Line {i + 1} temperature mismatch: expected {expected['temperature']}, got {row['temperature']}."


def run_extractor():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd='/home/user', text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Compiled extractor exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "Running the extractor did not create /home/user/anomalies.jsonl."


def test_extractor_program_and_output():
    # Preserve the original verifier's existence and exact-content assertions.
    assert os.path.isfile(EXTRACTOR), "The Go program /home/user/extractor.go is missing."
    assert_original_content(read_jsonl(OUTPUT))

    build = subprocess.run(
        ['go', 'build', '-o', BINARY, EXTRACTOR],
        cwd='/home/user', text=True, capture_output=True, timeout=120
    )
    assert build.returncode == 0, (
        f"extractor.go did not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    # Verify that execution, rather than a pre-created output file, produces the
    # required result for the supplied database.
    run_extractor()
    assert_original_content(read_jsonl(OUTPUT))

    backup = '/tmp/sensors-original.db'
    shutil.copy2(DATABASE, backup)
    token = secrets.token_hex(5)
    table = f'env_data_{token}'
    sensor_col = f'unitid_{token}'
    time_col = f'observed_{token}'
    temp_col = f'tempvalue_{token}'

    try:
        os.remove(DATABASE)
        conn = sqlite3.connect(DATABASE)
        conn.execute('CREATE TABLE metadata (version TEXT)')
        conn.execute("INSERT INTO metadata VALUES ('dynamic-test')")
        conn.execute('CREATE TABLE unrelated (id INTEGER PRIMARY KEY, note TEXT)')
        conn.execute(
            f'CREATE TABLE "{table}" ('
            'id INTEGER PRIMARY KEY, '
            f'"{sensor_col}" TEXT, '
            f'"{time_col}" DATETIME, '
            f'"{temp_col}" REAL, '
            'humidity REAL)'
        )

        rows = []
        start = datetime(2025, 2, 1, tzinfo=timezone.utc)
        # More than 50 qualifying rows exercises both ordering and LIMIT 50.
        for i in range(67):
            timestamp = (start + timedelta(minutes=i * 7)).strftime('%Y-%m-%dT%H:%M:%SZ')
            sensor = f'DYN-{token}-{i:03d}'
            temperature = round(20.25 + (i % 19) * 0.37 + i / 1000.0, 3)
            rows.append((sensor, timestamp, temperature, 30.0 + (i % 10)))
        for i in range(8):
            timestamp = (start + timedelta(minutes=500 + i)).strftime('%Y-%m-%dT%H:%M:%SZ')
            rows.append((f'COLD-{token}-{i}', timestamp, 20.0 if i == 0 else 18.0 + i / 10.0, 40.0))

        random.SystemRandom().shuffle(rows)
        conn.executemany(
            f'INSERT INTO "{table}" ("{sensor_col}", "{time_col}", "{temp_col}", humidity) VALUES (?, ?, ?, ?)',
            rows,
        )
        conn.commit()
        conn.close()

        expected = [
            {"sensor_id": sensor, "reading_time": timestamp, "temperature": temperature}
            for sensor, timestamp, temperature, _ in rows
            if temperature > 20.0
        ]
        expected.sort(key=lambda row: row['reading_time'], reverse=True)
        expected = expected[:50]

        run_extractor()
        actual = read_jsonl(OUTPUT)
        assert len(actual) == 50, f"Expected exactly 50 dynamically selected rows, found {len(actual)}."
        for i, (row, expected_row) in enumerate(zip(actual, expected)):
            assert set(row.keys()) == {'sensor_id', 'reading_time', 'temperature'}, (
                f"Dynamic output line {i + 1} must contain exactly sensor_id, reading_time, and temperature."
            )
            assert isinstance(row['sensor_id'], str), f"Dynamic output line {i + 1} sensor_id is not a string."
            assert isinstance(row['reading_time'], str), f"Dynamic output line {i + 1} reading_time is not a string."
            assert isinstance(row['temperature'], (int, float)) and not isinstance(row['temperature'], bool), (
                f"Dynamic output line {i + 1} temperature is not numeric."
            )
            assert row['sensor_id'] == expected_row['sensor_id']
            assert row['reading_time'] == expected_row['reading_time']
            assert float(row['temperature']) == pytest.approx(expected_row['temperature'])
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, DATABASE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
