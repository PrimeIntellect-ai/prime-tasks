#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import pytest

AUDIT_GO = "/home/user/audit.go"
REPORT = "/home/user/report.json"
DATABASE = "/app/compliance.db"


def load_report():
    assert os.path.isfile(REPORT), f"Report file not found at {REPORT}"
    try:
        with open(REPORT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT} is not valid JSON")


def assert_report(expected_server, expected_tuples):
    data = load_report()

    actual_server = data.get("server_audited")
    assert actual_server == expected_server, (
        f"Expected server_audited to be '{expected_server}', but got '{actual_server}'"
    )

    actual_tuples = set()
    for item in data.get("unauthorized_access", []):
        actual_tuples.add((item.get("user_id"), item.get("timestamp")))

    intersection = expected_tuples.intersection(actual_tuples)
    union = expected_tuples.union(actual_tuples)
    jaccard = 0.0 if not union else len(intersection) / len(union)

    assert jaccard >= 0.99, (
        f"Jaccard similarity {jaccard:.4f} is below threshold 0.99. "
        f"Expected {expected_tuples}, got {actual_tuples}"
    )


def run_audit():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["go", "run", AUDIT_GO],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"go run {AUDIT_GO} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"Running {AUDIT_GO} did not create {REPORT}"


def create_dynamic_database(path, unauthorized, authorized):
    conn = sqlite3.connect(path)
    c = conn.cursor()
    c.execute("CREATE TABLE access_logs (id INTEGER, server_name TEXT, user_id TEXT, timestamp INTEGER)")
    c.execute("CREATE TABLE kg_edges (subject TEXT, predicate TEXT, object TEXT)")
    c.execute("CREATE TABLE dummy (server_name TEXT)")
    c.execute("CREATE INDEX idx_dummy ON dummy(server_name)")

    row_id = 1
    for user_id, timestamp in unauthorized:
        c.execute("INSERT INTO access_logs VALUES (?, 'SERVER-82', ?, ?)", (row_id, user_id, timestamp))
        row_id += 1
    for user_id, timestamp in authorized:
        c.execute("INSERT INTO access_logs VALUES (?, 'SERVER-82', ?, ?)", (row_id, user_id, timestamp))
        c.execute("INSERT INTO kg_edges VALUES (?, 'CAN_ACCESS', 'SERVER-82')", (user_id,))
        row_id += 1

    c.execute("INSERT INTO access_logs VALUES (?, 'SERVER-99', ?, ?)",
              (row_id, unauthorized[0][0], unauthorized[0][1] + 77))
    c.execute("INSERT INTO kg_edges VALUES (?, 'CAN_ACCESS', 'SERVER-99')", (unauthorized[-1][0],))

    c.execute("PRAGMA writable_schema = ON")
    c.execute("UPDATE sqlite_master SET name='idx_server', tbl_name='access_logs', sql='CREATE INDEX idx_server ON access_logs(server_name)' WHERE name='idx_dummy'")
    c.execute("DELETE FROM sqlite_master WHERE name='dummy'")
    conn.commit()
    conn.close()


def test_report_accuracy_and_go_implementation():
    assert os.path.lexists(AUDIT_GO), f"Go implementation not found at {AUDIT_GO}"
    mode = os.lstat(AUDIT_GO).st_mode
    assert stat.S_ISREG(mode), f"{AUDIT_GO} must be a regular Go source file"
    assert os.path.getsize(AUDIT_GO) > 0, f"{AUDIT_GO} is empty"

    original_expected = {("U-909", 1672531100), ("U-112", 1672540000)}
    assert_report("SERVER-82", original_expected)

    token = secrets.token_hex(6).upper()
    base_timestamp = 1800000000 + secrets.randbelow(1000000)
    unauthorized = [
        (f"U-DYN-{token}-A", base_timestamp),
        (f"U-DYN-{token}-B", base_timestamp + 101),
    ]
    authorized = [(f"U-DYN-{token}-AUTH", base_timestamp + 202)]
    dynamic_expected = set(unauthorized)

    temp_dir = tempfile.mkdtemp(prefix="audit-verifier-")
    dynamic_db = os.path.join(temp_dir, "compliance.db")
    backup_db = os.path.join(temp_dir, "original.db")
    create_dynamic_database(dynamic_db, unauthorized, authorized)

    os.replace(DATABASE, backup_db)
    os.replace(dynamic_db, DATABASE)
    os.chmod(DATABASE, 0o777)
    try:
        run_audit()
        assert_report("SERVER-82", dynamic_expected)
    finally:
        if os.path.exists(DATABASE):
            os.remove(DATABASE)
        os.replace(backup_db, DATABASE)
        shutil.rmtree(temp_dir, ignore_errors=True)

    # Re-run against the original incident data and leave the required final report in place.
    run_audit()
    assert_report("SERVER-82", original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
