#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/project"
LIBHWMOCK = f"{PROJECT}/lib/libhwmock.so"
LIBMETRICS = f"{PROJECT}/lib/libmetrics.so"
DB_PATH = f"{PROJECT}/db/metrics.db"
SCRIPT_PATH = f"{PROJECT}/test_metrics.py"
OUTPUT_PATH = "/home/user/output.json"


def test_shared_libraries_exist():
    assert os.path.isfile(LIBHWMOCK), f"Shared library missing: {LIBHWMOCK}"
    assert os.path.isfile(LIBMETRICS), f"Shared library missing: {LIBMETRICS}"


def test_libraries_loadable_and_linked():
    try:
        ldd_output = subprocess.check_output(["ldd", LIBMETRICS], text=True)
        assert "libhwmock" in ldd_output, "libmetrics.so does not appear to be linked against libhwmock.so"
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run ldd on libmetrics.so")

    try:
        ctypes.CDLL(LIBHWMOCK, mode=ctypes.RTLD_GLOBAL)
    except Exception as e:
        pytest.fail(f"Failed to load libhwmock.so: {e}")

    try:
        metrics = ctypes.CDLL(LIBMETRICS)
    except Exception as e:
        pytest.fail(f"Failed to load libmetrics.so: {e}")

    metrics.get_system_score.restype = ctypes.c_double
    score = metrics.get_system_score()
    assert abs(score - 131.88) < 0.001, f"Expected get_system_score() to return ~131.88, got {score}"


def test_python_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing: {SCRIPT_PATH}"


def test_database_schema_and_data():
    assert os.path.isfile(DB_PATH), f"Database missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(results);")
        columns = {info[1]: info[2] for info in cursor.fetchall()}
        assert "status" in columns, "Column 'status' was not added to the results table"
        assert columns["status"].upper() == "TEXT", f"Column 'status' should be of type TEXT, got {columns['status']}"

        cursor.execute("SELECT id, metric_name, metric_value, status FROM results ORDER BY id ASC;")
        rows = cursor.fetchall()
        assert len(rows) == 2, f"Expected 2 rows in results table, found {len(rows)}"

        assert rows[0][0] == 1, "Row 1 id should be 1"
        assert rows[0][1] == "baseline", "Row 1 metric_name should be 'baseline'"
        assert rows[0][2] == 100.0, "Row 1 metric_value should be 100.0"
        assert rows[0][3] is None, "Row 1 status should be NULL"

        assert rows[1][0] == 2, "Row 2 id should be 2"
        assert rows[1][1] == "sys_score", "Row 2 metric_name should be 'sys_score'"
        assert abs(rows[1][2] - 131.88) < 0.001, "Row 2 metric_value should be ~131.88"
        assert rows[1][3] == "PASS", "Row 2 status should be 'PASS'"
    finally:
        conn.close()


def test_output_json():
    assert os.path.isfile(OUTPUT_PATH), f"Output JSON missing: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("output.json is not valid JSON")

    assert isinstance(data, list), "output.json should contain a JSON array"
    assert len(data) == 2, f"Expected 2 objects in output.json, found {len(data)}"

    required_keys = {"id", "metric_name", "metric_value", "status"}
    assert set(data[0]) == required_keys, "First object must have exactly the required keys"
    assert set(data[1]) == required_keys, "Second object must have exactly the required keys"

    assert data[0]["id"] == 1, "First object id should be 1"
    assert data[0]["metric_name"] == "baseline", "First object metric_name should be 'baseline'"
    assert data[0]["metric_value"] == 100.0, "First object metric_value should be 100.0"
    assert data[0]["status"] is None, "First object status should be null"

    assert data[1]["id"] == 2, "Second object id should be 2"
    assert data[1]["metric_name"] == "sys_score", "Second object metric_name should be 'sys_score'"
    assert abs(data[1]["metric_value"] - 131.88) < 0.001, "Second object metric_value should be ~131.88"
    assert data[1]["status"] == "PASS", "Second object status should be 'PASS'"

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT id, metric_name, metric_value, status FROM results ORDER BY id ASC"
        ).fetchall()
    finally:
        conn.close()
    expected = [
        {"id": row[0], "metric_name": row[1], "metric_value": row[2], "status": row[3]}
        for row in rows
    ]
    assert data == expected, "output.json must export the entire ordered results table"


def test_python_script_executes_pipeline_with_runtime_score():
    """Run the submitted script against a clean DB and a verifier-selected C result."""
    tempdir = tempfile.mkdtemp(prefix="metrics-verifier-")
    db_backup = os.path.join(tempdir, "metrics.db")
    output_backup = os.path.join(tempdir, "output.json")
    library_backup = os.path.join(tempdir, "libmetrics.so")
    fake_source = os.path.join(tempdir, "runtime_metrics.c")

    shutil.copy2(DB_PATH, db_backup)
    shutil.copy2(OUTPUT_PATH, output_backup)
    shutil.copy2(LIBMETRICS, library_backup)

    # A fractional verifier-selected value catches scripts that merely hard-code
    # the known 131.88 result or omit the c_double return signature.
    expected_score = 500.0 + secrets.randbelow(100000) / 1024.0

    try:
        with open(fake_source, "w") as f:
            f.write(f"double get_system_score(void) {{ return {expected_score.hex()}; }}\n")
        subprocess.run(
            ["gcc", "-shared", "-fPIC", fake_source, "-o", LIBMETRICS],
            check=True,
            capture_output=True,
            text=True,
        )

        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute(
                "CREATE TABLE results (id INTEGER PRIMARY KEY, metric_name TEXT, metric_value REAL, status TEXT)"
            )
            conn.execute(
                "INSERT INTO results (metric_name, metric_value, status) VALUES (?, ?, ?)",
                ("baseline", 100.0, None),
            )
            conn.commit()
        finally:
            conn.close()
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd=PROJECT,
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            "test_metrics.py failed when executed:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        conn = sqlite3.connect(DB_PATH)
        try:
            rows = conn.execute(
                "SELECT id, metric_name, metric_value, status FROM results ORDER BY id ASC"
            ).fetchall()
        finally:
            conn.close()

        assert rows == [
            (1, "baseline", 100.0, None),
            (2, "sys_score", expected_score, "PASS"),
        ], "Executing test_metrics.py must insert exactly the score returned by the loaded C library"

        assert os.path.isfile(OUTPUT_PATH), "Executing test_metrics.py did not create /home/user/output.json"
        with open(OUTPUT_PATH, "r") as f:
            exported = json.load(f)
        assert exported == [
            {"id": 1, "metric_name": "baseline", "metric_value": 100.0, "status": None},
            {"id": 2, "metric_name": "sys_score", "metric_value": expected_score, "status": "PASS"},
        ], "Executing test_metrics.py must export all rows with all required keys in id order"
    finally:
        shutil.copy2(library_backup, LIBMETRICS)
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(output_backup, OUTPUT_PATH)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
