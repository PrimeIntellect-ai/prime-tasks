#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIGINAL_DB="$(mktemp)"
cp /home/user/compliance.db "$ORIGINAL_DB"
trap 'cp "$ORIGINAL_DB" /home/user/compliance.db; rm -f "$ORIGINAL_DB"' EXIT

mkdir -p /tmp/audit_instrument
cat << 'PY_EOF' > /tmp/audit_instrument/sitecustomize.py
import os
import sqlite3

_real_connect = sqlite3.connect

def _traced_connect(*args, **kwargs):
    connection = _real_connect(*args, **kwargs)
    trace_path = os.environ.get("AUDIT_SQL_TRACE")
    if trace_path:
        def record(statement):
            with open(trace_path, "a", encoding="utf-8") as trace_file:
                trace_file.write(statement.replace("\x00", "") + "\n--STATEMENT--\n")
        connection.set_trace_callback(record)
    return connection

sqlite3.connect = _traced_connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/audit_pipeline.py"
OUTPUT_PATH = "/home/user/suspicious_users.json"
DB_PATH = "/home/user/compliance.db"
TRACE_PATH = "/tmp/audit_sql_trace.log"
INSTRUMENT_PATH = "/tmp/audit_instrument"


def expected_users():
    connection = sqlite3.connect(DB_PATH)
    try:
        rows = connection.execute(
            "SELECT user_id, tx_amount, tx_ts, rowid "
            "FROM system_tx_logs ORDER BY user_id, tx_ts, rowid"
        ).fetchall()
    finally:
        connection.close()

    by_user = {}
    for user_id, amount, _timestamp, _rowid in rows:
        by_user.setdefault(user_id, []).append(float(amount))

    return sorted(
        user_id
        for user_id, amounts in by_user.items()
        if any(sum(amounts[index:index + 3]) > 50000 for index in range(len(amounts) - 2))
    )


def run_pipeline(clear_trace=False):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    if clear_trace and os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    environment = os.environ.copy()
    environment["AUDIT_SQL_TRACE"] = TRACE_PATH
    environment["PYTHONPATH"] = INSTRUMENT_PATH + os.pathsep + environment.get("PYTHONPATH", "")
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=environment,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    assert os.path.exists(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    run_pipeline(clear_trace=True)


def load_output():
    assert os.path.exists(OUTPUT_PATH), f"Output JSON file missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file"
    with open(OUTPUT_PATH, "r", encoding="utf-8") as output_file:
        try:
            return json.load(output_file)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON")


def test_audit_pipeline_script_exists():
    """Test that the Python script was created."""
    assert os.path.exists(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_suspicious_users_json_exists():
    """Test that execution of the script created the output JSON file."""
    assert os.path.exists(OUTPUT_PATH), f"Output JSON file missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file"


def test_suspicious_users_json_content():
    """Test that the output contains the users actually meeting the rule."""
    data = load_output()
    assert "flagged_users" in data, "JSON missing 'flagged_users' key"
    flagged_users = data["flagged_users"]
    assert isinstance(flagged_users, list), "'flagged_users' must be a list"
    expected = expected_users()
    assert flagged_users == expected, f"Expected flagged users {expected}, but got {flagged_users}"


def test_executed_query_uses_sql_window_sum():
    assert os.path.isfile(TRACE_PATH), "The pipeline did not execute a traceable SQLite query"
    with open(TRACE_PATH, "r", encoding="utf-8") as trace_file:
        statements = trace_file.read().split("--STATEMENT--")
    matching = [
        statement for statement in statements
        if re.search(r"\bSUM\s*\(", statement, re.IGNORECASE)
        and re.search(r"\bOVER\b", statement, re.IGNORECASE)
        and re.search(r"\bsystem_tx_logs\b", statement, re.IGNORECASE)
    ]
    assert matching, "No executed transaction query used SUM as an SQL window function"


def test_pipeline_recomputes_from_changed_database():
    snapshot_handle, snapshot_path = tempfile.mkstemp(suffix=".db")
    os.close(snapshot_handle)
    shutil.copy2(DB_PATH, snapshot_path)

    random_flagged = "user_" + uuid.uuid4().hex
    random_safe = "user_" + uuid.uuid4().hex
    try:
        connection = sqlite3.connect(DB_PATH)
        try:
            connection.execute("UPDATE system_tx_logs SET tx_amount = 1000 WHERE tx_id = 't7'")
            base_time = 1900000000
            rows = []
            for index in range(3):
                rows.append((uuid.uuid4().hex, random_flagged, 17000, base_time + index))
                rows.append((uuid.uuid4().hex, random_safe, 16000, base_time + 100 + index))
            connection.executemany(
                "INSERT INTO system_tx_logs (tx_id, user_id, tx_amount, tx_ts) VALUES (?, ?, ?, ?)",
                rows,
            )
            connection.commit()
        finally:
            connection.close()

        run_pipeline()
        data = load_output()
        assert "flagged_users" in data, "JSON missing 'flagged_users' key"
        assert isinstance(data["flagged_users"], list), "'flagged_users' must be a list"
        expected = expected_users()
        assert data["flagged_users"] == expected, (
            f"Pipeline did not dynamically recompute results: expected {expected}, "
            f"got {data['flagged_users']}"
        )
    finally:
        shutil.copy2(snapshot_path, DB_PATH)
        os.remove(snapshot_path)
        run_pipeline()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
