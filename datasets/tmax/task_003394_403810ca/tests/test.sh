#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import time

OUTPUT_FILE = "/home/user/audit_summary.json"
SCRIPT_FILE = "/home/user/run_audit.py"
DB_FILE = "/app/audit_logs.db"


def load_output():
    with open(OUTPUT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {OUTPUT_FILE} is not valid JSON."


def expected_summary():
    conn = sqlite3.connect(DB_FILE)
    try:
        rows = conn.execute("""
            SELECT user_id, SUM(amount)
            FROM transactions
            WHERE risk_score > 8.0
            GROUP BY user_id
        """).fetchall()
    finally:
        conn.close()
    return [{"user_id": row[0], "total_amount": row[1]} for row in rows]


def assert_valid_summary(data, expected):
    assert isinstance(data, list), "Audit summary must be a JSON array."
    assert len(expected) > 0, "The audit database unexpectedly produced no high-risk results."
    for i, row in enumerate(data):
        assert isinstance(row, dict), f"Summary item {i} must be a JSON object."
        assert set(row) == {"user_id", "total_amount"}, \
            f"Summary item {i} has an incorrect schema: {sorted(row)}"
        assert isinstance(row["user_id"], int) and not isinstance(row["user_id"], bool), \
            f"Summary item {i} has an invalid user_id."
        assert isinstance(row["total_amount"], (int, float)) and not isinstance(row["total_amount"], bool), \
            f"Summary item {i} has an invalid total_amount."
    assert data == expected, "Audit summary does not match the high-risk transaction summary recomputed from the database."


def test_audit_summary_exists_and_valid():
    assert os.path.isfile(OUTPUT_FILE), \
        f"Output file {OUTPUT_FILE} does not exist. Did you run the script and save the output?"
    load_output()


def test_run_audit_speed():
    assert os.path.isfile(SCRIPT_FILE), f"Script file {SCRIPT_FILE} does not exist."

    expected = expected_summary()
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    start = time.time()
    result = subprocess.run(["python", SCRIPT_FILE], capture_output=True, text=True)
    elapsed = time.time() - start

    assert result.returncode == 0, \
        f"Script failed to run. Return code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert elapsed < 2.0, \
        f"Speedup not achieved. Took {elapsed:.2f} seconds, expected < 2.0s. The query optimization is not sufficient or the index was not used."
    assert os.path.isfile(OUTPUT_FILE), f"Script did not create {OUTPUT_FILE}."
    assert_valid_summary(load_output(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
