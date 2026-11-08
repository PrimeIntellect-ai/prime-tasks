#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import uuid

DB_PATH = "/home/user/audit_system.db"
QUERY_PLAN_PATH = "/home/user/query_plan.txt"
C_SOURCE_PATH = "/home/user/check_compliance.c"
EXECUTABLE_PATH = "/home/user/check_compliance"
VIOLATIONS_LOG_PATH = "/home/user/violations.log"
REBUILT_PATH = "/tmp/rebuilt_check_compliance"


def run_program(path):
    if os.path.exists(VIOLATIONS_LOG_PATH):
        os.remove(VIOLATIONS_LOG_PATH)
    result = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(VIOLATIONS_LOG_PATH), (
        f"{path} did not create {VIOLATIONS_LOG_PATH}"
    )


def read_violations():
    with open(VIOLATIONS_LOG_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_violations_from_database():
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("""
        SELECT s.name, s.clearance_doc, l.project_accessed
        FROM staff AS s
        JOIN restricted_access_logs AS l ON l.staff_id = s.id
    """).fetchall()
    conn.close()

    expected = []
    for name, clearance_doc, project in rows:
        projects = json.loads(clearance_doc)["projects"]
        if project not in projects:
            expected.append(f"{name} unauthorized access to {project}")
    return sorted(expected, key=lambda line: tuple(line.split(" unauthorized access to ", 1)))


def test_index_created():
    """Check the named index, its table, and the indexed foreign-key column."""
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name='idx_emp_access';")
    result = cursor.fetchone()

    assert result is not None, "Index 'idx_emp_access' was not found."
    assert result[1] == 'restricted_access_logs', f"Index 'idx_emp_access' is on wrong table: {result[1]}"

    columns = [row[2] for row in cursor.execute("PRAGMA index_info('idx_emp_access')")]
    conn.close()
    assert columns == ["staff_id"], f"idx_emp_access must index staff_id, but indexes: {columns}"


def test_query_plan_file():
    """Require a SQLite tree-form query plan containing both sides of a join."""
    assert os.path.exists(QUERY_PLAN_PATH), f"Query plan file missing at {QUERY_PLAN_PATH}"
    with open(QUERY_PLAN_PATH, "r") as f:
        content = f.read()
    upper = content.upper()

    # Preserve the original relevance assertion.
    assert "SCAN" in upper or "SEARCH" in upper or "IDX_EMP_ACCESS" in upper, \
        "The query plan file does not seem to contain a valid SQLite EXPLAIN QUERY PLAN output."

    lines = [line.rstrip() for line in content.splitlines() if line.strip()]
    assert lines and lines[0].strip().upper() == "QUERY PLAN", \
        "query_plan.txt must contain SQLite's EXPLAIN QUERY PLAN output, including its header."
    operation_lines = [
        line for line in lines[1:]
        if re.match(r"^\s*(?:\|--|`--)(?:SCAN|SEARCH)\b", line, re.IGNORECASE)
    ]
    assert len(operation_lines) >= 2, \
        "The query plan must show operations for both tables in the join."
    details = "\n".join(operation_lines).upper()
    assert "SCAN" in details or "SEARCH" in details
    assert (
        ("STAFF" in details and "RESTRICTED_ACCESS_LOGS" in details)
        or ("IDX_EMP_ACCESS" in details and "STAFF" in details)
        or ("INTEGER PRIMARY KEY" in details and len(operation_lines) >= 2)
    ), "The plan does not describe the required staff/access-log join."


def test_c_program_exists_and_is_compiled():
    """Check both source and the requested compiled executable, then rebuild the source."""
    assert os.path.exists(C_SOURCE_PATH), f"C source file missing at {C_SOURCE_PATH}"
    assert os.path.isfile(C_SOURCE_PATH) and os.path.getsize(C_SOURCE_PATH) > 0, \
        "C source file is empty or not a regular file."
    assert os.path.isfile(EXECUTABLE_PATH), f"Compiled program missing at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "check_compliance must be a compiled executable."

    result = subprocess.run(
        ["gcc", C_SOURCE_PATH, "-o", REBUILT_PATH, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"C source does not compile: {result.stderr}"


def test_program_generates_initial_violations_log():
    """Execute the submitted artifact and retain the original exact-output assertion."""
    run_program(EXECUTABLE_PATH)
    lines = read_violations()
    expected_lines = [
        "Bob Jones unauthorized access to Apollo",
        "Charlie Brown unauthorized access to Zeus"
    ]
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} violations, found {len(lines)}."
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Mismatch at line {i+1}. Expected: '{expected}', Got: '{lines[i]}'"


def test_program_computes_unseen_database_cases():
    """Add unpredictable cases and verify both the submitted binary and rebuilt source."""
    token = uuid.uuid4().hex
    conn = sqlite3.connect(DB_PATH)
    next_staff = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM staff").fetchone()[0]
    next_log = conn.execute("SELECT COALESCE(MAX(log_id), 0) + 1 FROM restricted_access_logs").fetchone()[0]

    name1 = f"Dynamic Alpha {token}"
    name2 = f"Dynamic Zulu {token}"
    allowed = f"Allowed-{token}"
    longer_allowed = f"Prefix-{token}-EXTRA"
    prefix_unauthorized = f"Prefix-{token}"
    forbidden = f"Forbidden-{token}"

    conn.execute(
        "INSERT INTO staff(id, name, clearance_doc) VALUES (?, ?, ?)",
        (next_staff, name1, json.dumps({"level": 99, "projects": [allowed, longer_allowed]}))
    )
    conn.execute(
        "INSERT INTO staff(id, name, clearance_doc) VALUES (?, ?, ?)",
        (next_staff + 1, name2, json.dumps({"level": 0, "projects": []}))
    )
    new_logs = [
        (next_log, next_staff, allowed),
        (next_log + 1, next_staff, forbidden),
        (next_log + 2, next_staff, prefix_unauthorized),
        (next_log + 3, next_staff + 1, allowed),
    ]
    conn.executemany(
        "INSERT INTO restricted_access_logs(log_id, staff_id, project_accessed) VALUES (?, ?, ?)",
        new_logs
    )
    conn.commit()
    conn.close()

    expected = expected_violations_from_database()
    for program in (EXECUTABLE_PATH, REBUILT_PATH):
        run_program(program)
        actual = read_violations()
        assert actual == expected, (
            f"{program} did not compute violations from the current database.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
