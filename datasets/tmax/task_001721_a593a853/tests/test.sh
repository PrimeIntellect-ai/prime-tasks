#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import sqlite3
import subprocess
from collections import Counter

import pytest

DB_PATH = '/home/user/metrics.db'
SCRIPT_PATH = '/home/user/infer.py'
RESULT_PATH = '/home/user/result.json'
SOURCE_PATH = '/home/user/server_logs.csv'


def load_result():
    assert os.path.isfile(RESULT_PATH), f"Result file not found at {RESULT_PATH}"
    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} does not contain valid JSON.")


def run_infer():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"infer.py exited with code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return load_result()


def assert_result(data, expected_mean):
    assert 'posterior_mean' in data, "Key 'posterior_mean' is missing from the JSON output."
    posterior_mean = data['posterior_mean']
    assert isinstance(posterior_mean, (int, float)), "The value for 'posterior_mean' must be a number."
    assert abs(posterior_mean - expected_mean) < 1e-5, (
        f"Expected posterior_mean to be {expected_mean}, but got {posterior_mean}."
    )


def test_database_exists_and_schema():
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='server_metrics'")
    table = cursor.fetchone()
    assert table is not None, "Table 'server_metrics' does not exist in the database."

    cursor.execute("PRAGMA table_info(server_metrics)")
    columns = {row[1]: row[2] for row in cursor.fetchall()}

    expected_columns = {
        'timestamp': 'TEXT',
        'latency_sec': 'REAL',
        'status': 'TEXT'
    }

    for col_name, col_type in expected_columns.items():
        assert col_name in columns, f"Column '{col_name}' is missing from 'server_metrics'."
        assert columns[col_name].upper() == col_type, f"Column '{col_name}' should be of type {col_type}, but got {columns[col_name]}."

    conn.close()


def test_database_content():
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM server_metrics")
    count = cursor.fetchone()[0]
    assert count == 100, f"Expected 100 rows in 'server_metrics', found {count}."

    cursor.execute("SELECT latency_sec, status FROM server_metrics")
    rows = cursor.fetchall()

    fails = sum(1 for row in rows if row[1] == 'FAIL')
    oks = sum(1 for row in rows if row[1] == 'OK')

    assert fails == 14, f"Expected 14 FAIL records in database, found {fails}."
    assert oks == 86, f"Expected 86 OK records in database, found {oks}."

    for latency, status in rows:
        if status == 'FAIL':
            assert abs(latency - 1.2) < 1e-5, f"Expected latency_sec for FAIL to be 1.2, got {latency}"
        elif status == 'OK':
            assert abs(latency - 0.15) < 1e-5, f"Expected latency_sec for OK to be 0.15, got {latency}"

    conn.close()


def test_database_matches_source_rows():
    expected = []
    with open(SOURCE_PATH, newline='') as f:
        for row in csv.DictReader(f):
            if row['server_id'] == 'SRV-001':
                expected.append((row['timestamp'], float(row['latency_ms']) / 1000.0, row['status']))

    conn = sqlite3.connect(DB_PATH)
    actual = conn.execute(
        "SELECT timestamp, latency_sec, status FROM server_metrics"
    ).fetchall()
    conn.close()

    assert Counter(actual) == Counter(expected), (
        "Rows in server_metrics do not exactly match the SRV-001 rows transformed from server_logs.csv."
    )


def test_infer_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python script not found at {SCRIPT_PATH}"


def test_result_json():
    data = run_infer()
    expected_mean = 0.1429
    assert_result(data, expected_mean)


def test_infer_uses_database_counts():
    conn = sqlite3.connect(DB_PATH)
    original_rows = conn.execute(
        "SELECT timestamp, status FROM server_metrics ORDER BY timestamp"
    ).fetchall()
    conn.close()
    assert len(original_rows) == 100

    original_result = None
    if os.path.isfile(RESULT_PATH):
        with open(RESULT_PATH, 'rb') as f:
            original_result = f.read()

    rng = secrets.SystemRandom()
    candidate_counts = [n for n in range(0, 101) if n != 14]
    fail_counts = rng.sample(candidate_counts, 2)
    timestamps = [row[0] for row in original_rows]

    try:
        for fail_count in fail_counts:
            failing_timestamps = set(rng.sample(timestamps, fail_count))
            conn = sqlite3.connect(DB_PATH)
            conn.execute("UPDATE server_metrics SET status = 'OK'")
            conn.executemany(
                "UPDATE server_metrics SET status = 'FAIL' WHERE timestamp = ?",
                [(timestamp,) for timestamp in failing_timestamps],
            )
            conn.commit()
            conn.close()

            data = run_infer()
            expected_mean = round((2 + fail_count) / (2 + 10 + len(timestamps)), 4)
            assert_result(data, expected_mean)
    finally:
        conn = sqlite3.connect(DB_PATH)
        conn.executemany(
            "UPDATE server_metrics SET status = ? WHERE timestamp = ?",
            [(status, timestamp) for timestamp, status in original_rows],
        )
        conn.commit()
        conn.close()

        if original_result is not None:
            with open(RESULT_PATH, 'wb') as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
