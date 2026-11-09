#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sys
import json
import glob
import sqlite3
import subprocess
from collections import Counter

import pytest

RAW_BACKUPS_PATH = "/home/user/raw_backups.jsonl"
DB_PATH = "/home/user/backups.db"
ANOMALIES_PATH = "/home/user/anomalies.json"
TRACE_PATH = "/tmp/submission_sql_trace.json"
EXECUTED_SQL_RUNS = []


def get_normalized_data():
    if not os.path.exists(RAW_BACKUPS_PATH):
        pytest.fail(f"Raw backups file missing at {RAW_BACKUPS_PATH}")

    records = []
    with open(RAW_BACKUPS_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)

            db_name = data.get('database') or data.get('db')

            status = data.get('status') or data.get('state')
            if status == "ok":
                status = "success"

            if 'size' in data:
                size_bytes = data['size']
            else:
                size_bytes = data['metrics']['bytes']

            timestamp = data.get('ts') or data.get('time')

            records.append({
                "database_name": db_name,
                "status": status,
                "size_bytes": size_bytes,
                "timestamp": timestamp
            })
    return records


def compute_expected_anomalies(records):
    # Sort chronologically to compute rolling averages
    records.sort(key=lambda x: x['timestamp'])

    history = {}
    anomalies = []

    for r in records:
        db_name = r['database_name']
        status = r['status']
        size = r['size_bytes']
        ts = r['timestamp']

        if db_name not in history:
            history[db_name] = []

        if status == "success":
            prev_successes = history[db_name][-3:]
            if len(prev_successes) > 0:
                rolling_avg = sum(prev_successes) / len(prev_successes)
                if size > 1.2 * rolling_avg:
                    anomalies.append({
                        "database_name": db_name,
                        "timestamp": ts,
                        "size_bytes": size,
                        "rolling_avg": round(rolling_avg, 1)
                    })
            history[db_name].append(size)

    # Sort globally by timestamp descending
    anomalies.sort(key=lambda x: x['timestamp'], reverse=True)
    return anomalies


def find_submission_script():
    candidates = []
    for path in glob.glob('/home/user/**/*.py', recursive=True):
        if not os.path.isfile(path):
            continue
        try:
            with open(path, 'r', encoding='utf-8') as f:
                source = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        score = sum(token in source for token in (
            'raw_backups.jsonl', 'backups.db', 'anomalies.json',
            'backup_runs', 'sqlite3'
        ))
        if score >= 3:
            candidates.append((score, path))
    assert candidates, "No Python submission script that processes the required files was found under /home/user."
    candidates.sort(key=lambda item: (-item[0], item[1]))
    return candidates[0][1]


def run_submission(script):
    for path in (DB_PATH, ANOMALIES_PATH, TRACE_PATH):
        if os.path.exists(path):
            os.remove(path)

    runner = r'''
import json
import runpy
import sqlite3
import sys

script, trace_path = sys.argv[1], sys.argv[2]
statements = []
real_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    conn = real_connect(*args, **kwargs)
    conn.set_trace_callback(statements.append)
    return conn

sqlite3.connect = traced_connect
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with open(trace_path, "w") as f:
        json.dump(statements, f)
'''
    with open('/tmp/run_submission.py', 'w') as f:
        f.write(runner)

    result = subprocess.run(
        [sys.executable, '/tmp/run_submission.py', script, TRACE_PATH],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Submission script failed when executed.\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.exists(TRACE_PATH), "Could not capture SQL executed by the submission script."
    with open(TRACE_PATH, 'r') as f:
        statements = json.load(f)
    return statements


def assert_window_sql(statements):
    matching = []
    for statement in statements:
        sql = re.sub(r'\s+', ' ', statement.upper())
        sql = re.sub(r'["`\[\]]', '', sql)
        has_frame = (
            re.search(r'ROWS\s+BETWEEN\s+3\s+PRECEDING\s+AND\s+1\s+PRECEDING', sql)
            or (
                re.search(r'ROWS\s+BETWEEN\s+3\s+PRECEDING\s+AND\s+CURRENT\s+ROW', sql)
                and 'EXCLUDE CURRENT ROW' in sql
            )
        )
        if (re.search(r'\bAVG\s*\(', sql)
                and re.search(r'\bOVER\s*\(', sql)
                and re.search(r'PARTITION\s+BY\s+(?:\w+\.)?DATABASE_NAME', sql)
                and 'ORDER BY' in sql and 'TIMESTAMP' in sql and has_frame):
            matching.append(statement)
    assert matching, (
        "The executed SQL did not use AVG as a window function partitioned by "
        "database_name and ordered by timestamp over the previous 3 rows while "
        "excluding the current row."
    )


def assert_database_matches(records):
    assert os.path.exists(DB_PATH), f"SQLite database not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        info = conn.execute("PRAGMA table_info(backup_runs)").fetchall()
        assert info, "Table 'backup_runs' does not exist in the SQLite database."
        columns = {row[1]: row[2].upper() for row in info}
        required = {'database_name', 'status', 'size_bytes', 'timestamp'}
        assert required.issubset(columns), (
            f"backup_runs is missing normalized columns: {sorted(required - set(columns))}"
        )
        assert any(x in columns['database_name'] for x in ('CHAR', 'CLOB', 'TEXT')), "database_name must have TEXT affinity."
        assert any(x in columns['status'] for x in ('CHAR', 'CLOB', 'TEXT')), "status must have TEXT affinity."
        assert 'INT' in columns['size_bytes'], "size_bytes must have INTEGER affinity."
        assert any(x in columns['timestamp'] for x in ('CHAR', 'CLOB', 'TEXT')), "timestamp must have TEXT affinity."

        actual = conn.execute(
            "SELECT database_name, status, size_bytes, timestamp FROM backup_runs"
        ).fetchall()
        expected = [
            (r['database_name'], r['status'], r['size_bytes'], r['timestamp'])
            for r in records
        ]
        assert Counter(actual) == Counter(expected), (
            "Rows in backup_runs do not exactly match the normalized raw records."
        )
    finally:
        conn.close()


def assert_report_matches(records):
    assert os.path.exists(ANOMALIES_PATH), f"Anomalies JSON output not found at {ANOMALIES_PATH}"
    with open(ANOMALIES_PATH, 'r') as f:
        output = json.load(f)
    anomalies = compute_expected_anomalies([dict(r) for r in records])
    assert output.get('page') == 1
    assert output.get('page_size') == 2
    assert output.get('total_anomalies') == len(anomalies)
    assert output.get('data') == anomalies[:2]


@pytest.fixture(scope='session', autouse=True)
def execute_and_probe_submission():
    script = find_submission_script()
    with open(RAW_BACKUPS_PATH, 'rb') as f:
        original_raw = f.read()

    probe = [
        {"database": "alpha", "status": "success", "metrics": {"bytes": 100}, "ts": "2025-01-01T00:00:00Z"},
        {"db": "alpha", "state": "ok", "size": 110, "time": "2025-01-02T00:00:00Z"},
        {"database": "alpha", "status": "failed", "metrics": {"bytes": 9999}, "ts": "2025-01-03T00:00:00Z"},
        {"db": "alpha", "state": "success", "size": 90, "time": "2025-01-04T00:00:00Z"},
        {"database": "alpha", "status": "success", "metrics": {"bytes": 160}, "ts": "2025-01-05T00:00:00Z"},
        {"database": "beta", "status": "success", "metrics": {"bytes": 400}, "ts": "2025-01-01T01:00:00Z"},
        {"db": "beta", "state": "ok", "size": 700, "time": "2025-01-06T01:00:00Z"},
        {"database": "alpha", "status": "success", "metrics": {"bytes": 250}, "ts": "2025-01-07T00:00:00Z"}
    ]

    try:
        with open(RAW_BACKUPS_PATH, 'w') as f:
            for item in probe:
                f.write(json.dumps(item) + '\n')
        probe_records = get_normalized_data()
        probe_sql = run_submission(script)
        assert_window_sql(probe_sql)
        assert_database_matches(probe_records)
        assert_report_matches(probe_records)
    finally:
        with open(RAW_BACKUPS_PATH, 'wb') as f:
            f.write(original_raw)

    original_sql = run_submission(script)
    assert_window_sql(original_sql)
    EXECUTED_SQL_RUNS.append(original_sql)


def test_sqlite_database_created_and_populated():
    assert os.path.exists(DB_PATH), f"SQLite database not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='backup_runs'")
    table_exists = cursor.fetchone()
    assert table_exists, "Table 'backup_runs' does not exist in the SQLite database."

    cursor.execute("SELECT COUNT(*) FROM backup_runs")
    count = cursor.fetchone()[0]

    expected_records = get_normalized_data()
    assert count == len(expected_records), f"Expected {len(expected_records)} rows in backup_runs, got {count}."

    conn.close()

    # Verify the normalized schema and every stored value, not only the row count.
    assert_database_matches(expected_records)


def test_anomalies_json_output():
    assert os.path.exists(ANOMALIES_PATH), f"Anomalies JSON output not found at {ANOMALIES_PATH}"

    with open(ANOMALIES_PATH, 'r') as f:
        try:
            output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {ANOMALIES_PATH} is not valid JSON.")

    expected_records = get_normalized_data()
    all_anomalies = compute_expected_anomalies(expected_records)

    assert "page" in output, "Missing 'page' key in JSON output."
    assert output["page"] == 1, f"Expected page 1, got {output['page']}."

    assert "page_size" in output, "Missing 'page_size' key in JSON output."
    assert output["page_size"] == 2, f"Expected page_size 2, got {output['page_size']}."

    assert "total_anomalies" in output, "Missing 'total_anomalies' key in JSON output."
    assert output["total_anomalies"] == len(all_anomalies), f"Expected total_anomalies {len(all_anomalies)}, got {output['total_anomalies']}."

    assert "data" in output, "Missing 'data' key in JSON output."
    assert isinstance(output["data"], list), "'data' should be a list."

    expected_page_data = all_anomalies[:2]

    assert len(output["data"]) == len(expected_page_data), f"Expected {len(expected_page_data)} items in 'data', got {len(output['data'])}."

    for i, (actual, expected) in enumerate(zip(output["data"], expected_page_data)):
        assert actual.get("database_name") == expected["database_name"], f"Mismatch in database_name at index {i}"
        assert actual.get("timestamp") == expected["timestamp"], f"Mismatch in timestamp at index {i}"
        assert actual.get("size_bytes") == expected["size_bytes"], f"Mismatch in size_bytes at index {i}"

        actual_avg = actual.get("rolling_avg")
        expected_avg = expected["rolling_avg"]
        assert actual_avg == expected_avg, f"Mismatch in rolling_avg at index {i}. Expected {expected_avg}, got {actual_avg}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
