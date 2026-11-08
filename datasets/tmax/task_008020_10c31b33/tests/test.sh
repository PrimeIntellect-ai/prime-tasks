#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import shutil
import sqlite3
import subprocess
import tempfile
import uuid
from collections import Counter

import pytest

DB_PATH = "/home/user/sensor_data.db"
CSV_PATH = "/home/user/sensors.csv"
PLAN_PATH = "/home/user/query_plan.txt"
SOURCE_PATH = "/home/user/exporter.c"
EXE_PATH = "/home/user/exporter"
OUT_PATH = "/home/user/anomalies.txt"
QUERY = "SELECT sensor_id, temperature FROM readings WHERE status = 'ERROR' AND temperature > 80.0 ORDER BY timestamp DESC;"


def test_db_exists_and_data_imported():
    """Check that the database has the proper schema and exactly imports the CSV."""
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}."

    expected = []
    with open(CSV_PATH, newline='') as f:
        for row in csv.reader(f):
            if row:
                expected.append((int(row[0]), row[1], float(row[2]), float(row[3]), row[4]))

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT COUNT(*) FROM readings")
            count = cursor.fetchone()[0]
            cursor.execute("SELECT timestamp, sensor_id, temperature, humidity, status FROM readings")
            actual = cursor.fetchall()
            cursor.execute("PRAGMA table_info(readings)")
            schema = cursor.fetchall()
        except sqlite3.OperationalError as e:
            pytest.fail(f"Failed to query 'readings' table: {e}")
    finally:
        conn.close()

    assert count == 10000, f"Expected 10000 rows in 'readings' table, found {count}."
    assert Counter(actual) == Counter(expected), "The readings table does not exactly match sensors.csv."

    columns = [(row[1], row[2].upper()) for row in schema]
    assert [name for name, _ in columns] == [
        "timestamp", "sensor_id", "temperature", "humidity", "status"
    ], f"Unexpected readings schema: {columns}"
    expected_affinities = ["INT", "TEXT", "REAL", "REAL", "TEXT"]
    for (name, declared_type), affinity in zip(columns, expected_affinities):
        assert affinity in declared_type, f"Column {name} has inappropriate type {declared_type!r}."


def test_query_plan_optimal():
    """Recompute EXPLAIN QUERY PLAN and verify the submitted exact output and optimization."""
    assert os.path.isfile(PLAN_PATH), f"Query plan file not found at {PLAN_PATH}."

    result = subprocess.run(
        ["sqlite3", DB_PATH, "EXPLAIN QUERY PLAN " + QUERY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"EXPLAIN QUERY PLAN failed: {result.stderr}"

    with open(PLAN_PATH, 'r') as f:
        submitted = f.read()
    assert submitted == result.stdout, \
        "query_plan.txt is not the exact output of EXPLAIN QUERY PLAN for the required query."

    content = submitted.upper()
    assert "USING INDEX" in content or "USING COVERING INDEX" in content, \
        "The query plan does not indicate that an index is being used."
    assert "TEMP B-TREE FOR ORDER BY" not in content and "B-TREE FOR ORDER BY" not in content, \
        "The query plan indicates a separate sorting pass (TEMP B-TREE FOR ORDER BY) is used, which is not optimal."


def test_exporter_files_exist():
    """Check that the C source code and compiled executable exist."""
    assert os.path.isfile(SOURCE_PATH), f"C source file not found at {SOURCE_PATH}."
    assert os.path.isfile(EXE_PATH), f"Compiled executable not found at {EXE_PATH}."
    assert os.access(EXE_PATH, os.X_OK), f"File at {EXE_PATH} is not executable."


def test_anomalies_output():
    """Check that anomalies.txt contains the correct output for the imported CSV."""
    assert os.path.isfile(CSV_PATH), "Original CSV file missing."
    assert os.path.isfile(OUT_PATH), f"Output file not found at {OUT_PATH}."

    expected_records = []
    with open(CSV_PATH, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or len(row) < 5:
                continue
            ts = int(row[0])
            sensor = row[1]
            temp = float(row[2])
            status = row[4]
            if status == 'ERROR' and temp > 80.0:
                expected_records.append((ts, sensor, temp))

    expected_records.sort(key=lambda x: x[0], reverse=True)
    expected_lines = [f"ALERT: [{rec[1]}] registered {rec[2]:.1f}C" for rec in expected_records]

    with open(OUT_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in anomalies.txt, found {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}: expected '{expected}', got '{actual}'."


def test_recompiled_exporter_executes_query():
    """Recompile and execute the C source against verifier-generated database rows."""
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-lsqlite3", "-o", EXE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Failed to compile exporter.c: {compile_result.stderr}"
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)

    fd, backup_path = tempfile.mkstemp(prefix="sensor_data_backup_", suffix=".db")
    os.close(fd)
    saved_output = None
    output_existed = os.path.exists(OUT_PATH)
    if output_existed:
        with open(OUT_PATH, "rb") as f:
            saved_output = f.read()

    source_conn = sqlite3.connect(DB_PATH)
    backup_conn = sqlite3.connect(backup_path)
    try:
        source_conn.backup(backup_conn)
    finally:
        source_conn.close()
        backup_conn.close()

    token = uuid.uuid4().hex
    sensor_newer = "VERIFY_NEWER_" + token
    sensor_older = "VERIFY_OLDER_" + token

    run_result = None
    produced_lines = None
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("DELETE FROM readings")
            conn.executemany(
                "INSERT INTO readings(timestamp, sensor_id, temperature, humidity, status) VALUES (?, ?, ?, ?, ?)",
                [
                    (900000030, sensor_newer, 99.4, 45.0, "ERROR"),
                    (900000010, sensor_older, 81.1, 46.0, "ERROR"),
                    (900000040, "VERIFY_LOW_" + token, 77.0, 47.0, "ERROR"),
                    (900000050, "VERIFY_OK_" + token, 95.0, 48.0, "OK"),
                    (900000020, "VERIFY_WARNING_" + token, 88.8, 49.0, "WARNING"),
                    (900000060, "VERIFY_BOUNDARY_" + token, 80.0, 50.0, "ERROR"),
                ],
            )
            conn.commit()
        finally:
            conn.close()

        if os.path.exists(OUT_PATH):
            os.remove(OUT_PATH)

        run_result = subprocess.run(
            [EXE_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        if os.path.isfile(OUT_PATH):
            with open(OUT_PATH, 'r') as f:
                produced_lines = [line.strip() for line in f if line.strip()]
    finally:
        restore_source = sqlite3.connect(backup_path)
        restore_target = sqlite3.connect(DB_PATH)
        try:
            restore_source.backup(restore_target)
        finally:
            restore_source.close()
            restore_target.close()
        os.remove(backup_path)

        if output_existed:
            with open(OUT_PATH, "wb") as f:
                f.write(saved_output)
        elif os.path.exists(OUT_PATH):
            os.remove(OUT_PATH)

    assert run_result is not None and run_result.returncode == 0, \
        f"Recompiled exporter failed: {run_result.stderr if run_result else 'not run'}"
    assert produced_lines is not None, "The recompiled exporter did not create anomalies.txt."
    assert produced_lines == [
        f"ALERT: [{sensor_newer}] registered 99.4C",
        f"ALERT: [{sensor_older}] registered 81.1C",
    ], "The recompiled exporter did not execute the required database query and formatting."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
