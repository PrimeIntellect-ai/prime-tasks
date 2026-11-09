#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

import pytest

DB_PATH = "/home/user/climate_data.db"
SCRIPT_PATH = "/home/user/generate_report.py"
REPORT_PATH = "/home/user/alpine_temp_report.json"
BASELINE_PATH = "/var/lib/climate_task/original.db"
TABLES = ("locations", "sensors", "readings")


def table_rows(db_path, table):
    conn = sqlite3.connect(db_path)
    try:
        return conn.execute(f'SELECT * FROM "{table}" ORDER BY id').fetchall()
    finally:
        conn.close()


def assert_database_data_unchanged():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.exists(BASELINE_PATH), "Verifier baseline is missing"
    for table in TABLES:
        assert table_rows(DB_PATH, table) == table_rows(BASELINE_PATH, table), \
            f"Data in table {table} was deleted or altered"


def expected_report(db_path):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute("""
            SELECT r.sensor_id, r.timestamp, r.value,
                   ROUND(AVG(r.value) OVER (
                       PARTITION BY r.sensor_id
                       ORDER BY r.timestamp
                       ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
                   ), 2) AS moving_avg
            FROM readings r
            JOIN sensors s ON r.sensor_id = s.id
            JOIN locations l ON s.location_id = l.id
            WHERE s.type = 'TEMP' AND l.region_name = 'Alpine_Zone'
            ORDER BY r.sensor_id ASC, r.timestamp ASC
        """).fetchall()
    finally:
        conn.close()
    return [
        {"sensor_id": r[0], "timestamp": r[1], "value": r[2], "moving_avg": r[3]}
        for r in rows
    ]


def load_report():
    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    try:
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT_PATH} does not contain valid JSON: {exc}")


RUNNER = r'''
import importlib.util
import json
import os
import sqlite3
import sys

target_db, trace_path = sys.argv[1], sys.argv[2]
real_connect = sqlite3.connect
statements = []

def checked_connect(database, *args, **kwargs):
    try:
        requested = os.fspath(database)
    except TypeError:
        requested = database
    if requested == "/home/user/climate_data.db":
        database = target_db
    conn = real_connect(database, *args, **kwargs)
    conn.set_trace_callback(statements.append)
    return conn

sqlite3.connect = checked_connect
spec = importlib.util.spec_from_file_location("submitted_generate_report", "/home/user/generate_report.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "run", None)):
    raise RuntimeError("generate_report.py must define a callable run()")
module.run()
with open(trace_path, "w", encoding="utf-8") as f:
    json.dump(statements, f)
'''


def execute_submission(target_db):
    fd, trace_path = tempfile.mkstemp(prefix="climate_trace_", suffix=".json")
    os.close(fd)
    try:
        result = subprocess.run(
            [sys.executable, "-c", RUNNER, target_db, trace_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, \
            f"generate_report.py failed when executed:\n{result.stdout}{result.stderr}"
        with open(trace_path, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(trace_path):
            os.unlink(trace_path)


def assert_optimized_query(statements):
    selects = [s for s in statements if re.search(r"\bSELECT\b", s, re.I)]
    assert len(selects) == 1, \
        f"Expected one SQL SELECT query for the report, observed {len(selects)}: {selects}"
    sql = re.sub(r"\s+", " ", selects[0]).upper()
    assert "READINGS" in sql and "SENSORS" in sql and "LOCATIONS" in sql
    assert len(re.findall(r"\bJOIN\b", sql)) >= 2, "The report query must perform both JOINs in SQL"
    assert re.search(r"\bOVER\s*\(", sql), "The report query must use a window function"
    assert re.search(r"\bPARTITION\s+BY\b", sql), "The window must use PARTITION BY"
    assert re.search(r"ROWS\s+BETWEEN\s+2\s+PRECEDING\s+AND\s+CURRENT\s+ROW", sql), \
        "The window must cover the current reading and two preceding readings"
    assert "TEMP" in sql and "ALPINE_ZONE" in sql, "The filtering must be performed by the SQL query"


def test_indexes_created_and_relevant():
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = conn.execute("""
            SELECT name, tbl_name
            FROM sqlite_master
            WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'
        """).fetchall()
        assert len(indexes) >= 2, \
            f"Expected at least 2 user-created indexes, but found {len(indexes)}: {indexes}"

        useful = []
        relevant_leading_columns = {
            "readings": {"sensor_id"},
            "sensors": {"type", "location_id"},
            "locations": {"region_name"},
        }
        for name, table in indexes:
            escaped = name.replace('"', '""')
            columns = [row[2] for row in conn.execute(f'PRAGMA index_info("{escaped}")')]
            if columns and columns[0] in relevant_leading_columns.get(table, set()):
                useful.append((name, table, columns))
        assert len(useful) >= 2, \
            f"At least two indexes must lead with join/filter columns; useful indexes found: {useful}"
    finally:
        conn.close()


def test_script_and_report():
    assert_database_data_unchanged()
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode) and not stat.S_ISLNK(mode), \
        f"{SCRIPT_PATH} must be a regular Python file"

    fixture_fd, fixture_path = tempfile.mkstemp(prefix="climate_fixture_", suffix=".db")
    os.close(fixture_fd)
    shutil.copyfile(BASELINE_PATH, fixture_path)
    try:
        conn = sqlite3.connect(fixture_path)
        conn.execute("INSERT INTO locations(id, region_name, elevation) VALUES (101, 'Alpine_Zone', 2222)")
        conn.execute("INSERT INTO sensors(id, type, location_id) VALUES (99, 'TEMP', 101)")
        conn.executemany(
            "INSERT INTO readings(sensor_id, timestamp, value) VALUES (?, ?, ?)",
            [
                (99, "2040-05-01T00:00:00", 101.0),
                (99, "2040-05-01T01:00:00", 203.0),
                (99, "2040-05-01T02:00:00", -17.0),
                (99, "2040-05-01T03:00:00", 44.0),
            ],
        )
        conn.commit()
        conn.close()

        trace = execute_submission(fixture_path)
        assert_optimized_query(trace)
        assert load_report() == expected_report(fixture_path), \
            "The executed script did not produce the correct report for verifier-derived input"
    finally:
        if os.path.exists(fixture_path):
            os.unlink(fixture_path)

    trace = execute_submission(DB_PATH)
    assert_optimized_query(trace)
    assert load_report() == expected_report(BASELINE_PATH), \
        "The generated JSON report does not match the expected output."
    assert_database_data_unchanged()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
