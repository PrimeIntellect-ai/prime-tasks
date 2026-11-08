#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import importlib.util
import math
import os
import re
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/calculate_sla.py"
RESULT_PATH = "/home/user/sla_penalty_result.txt"
DB_PATH = "/home/user/uptime.db"


def load_submission():
    spec = importlib.util.spec_from_file_location("calculate_sla_submission", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, f"Could not load {SCRIPT_PATH}."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected_total(rows):
    total = 0
    for start, end, sev in rows:
        duration = end - start
        if duration > 0:
            chunks = math.ceil(duration / 60.0)
            total += chunks * (sev * 10)
    return total


def test_script_executes_successfully():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), f"Running {SCRIPT_PATH} did not generate {RESULT_PATH}."


def test_recursive_penalty_function():
    module = load_submission()
    assert callable(getattr(module, "compute_cascade_penalty", None)), (
        "compute_cascade_penalty is missing or is not callable."
    )

    cases = [
        (0, 2, 0),
        (1, 2, 20),
        (59, 3, 30),
        (60, 4, 40),
        (61, 2, 40),
        (120, 3, 60),
        (150, 2, 60),
    ]
    for duration, severity, expected in cases:
        actual = module.compute_cascade_penalty(duration, severity)
        assert actual == expected, (
            f"compute_cascade_penalty({duration}, {severity}) returned {actual}; "
            f"expected {expected}."
        )


def test_calculation_queries_only_valid_incidents(monkeypatch):
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    original_connect = sqlite3.connect
    expected_conn = original_connect(DB_PATH)
    expected_cursor = expected_conn.cursor()
    expected_cursor.execute(
        "SELECT start_time, end_time, severity FROM incidents "
        "WHERE end_time >= start_time AND severity > 0"
    )
    expected_rows = expected_cursor.fetchall()
    expected_conn.close()

    selected_batches = []

    class RecordingCursor:
        def __init__(self, cursor):
            self._cursor = cursor

        def execute(self, *args, **kwargs):
            self._cursor.execute(*args, **kwargs)
            return self

        def fetchall(self):
            rows = self._cursor.fetchall()
            selected_batches.append(list(rows))
            return rows

        def __getattr__(self, name):
            return getattr(self._cursor, name)

    class RecordingConnection:
        def __init__(self, connection):
            self._connection = connection

        def cursor(self):
            return RecordingCursor(self._connection.cursor())

        def __getattr__(self, name):
            return getattr(self._connection, name)

    module = load_submission()
    assert callable(getattr(module, "calculate_total_penalty", None)), (
        "calculate_total_penalty is missing or is not callable."
    )

    monkeypatch.setattr(
        module.sqlite3,
        "connect",
        lambda path, *args, **kwargs: RecordingConnection(
            original_connect(path, *args, **kwargs)
        ),
    )

    actual_total = module.calculate_total_penalty()
    assert selected_batches, "calculate_total_penalty did not fetch incidents from the database."
    assert collections.Counter(selected_batches[0]) == collections.Counter(expected_rows), (
        "The incident query did not return exactly the rows satisfying "
        "end_time >= start_time and severity > 0."
    )
    assert actual_total == expected_total(expected_rows), (
        f"calculate_total_penalty returned {actual_total}; "
        f"expected {expected_total(expected_rows)}."
    )


def test_sla_penalty_result_exists():
    assert os.path.exists(RESULT_PATH), f"Result file {RESULT_PATH} is missing."
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a file."


def test_sla_penalty_result_value():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT start_time, end_time, severity FROM incidents "
        "WHERE end_time >= start_time AND severity > 0"
    )
    valid_incidents = cursor.fetchall()
    conn.close()

    expected = expected_total(valid_incidents)

    with open(RESULT_PATH, "r") as f:
        result_content = f.read()

    assert re.fullmatch(r"[0-9]+", result_content), (
        f"Result file {RESULT_PATH} does not contain only a valid integer. "
        f"Found: {result_content!r}"
    )
    assert int(result_content) == expected, (
        f"Expected SLA penalty score to be {expected}, but found {result_content}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
