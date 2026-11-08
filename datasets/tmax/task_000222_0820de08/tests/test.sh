#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "violations.csv")
SOURCE_PATH = os.path.join(HOME, "audit.c")
DB_PATH = os.path.join(HOME, "audit.db")
LOG_PATH = os.path.join(HOME, "logs.json")
BINARY_PATH = "/tmp/audit_submission"
HEADER = ["timestamp", "user_name", "department_name", "resource_id", "action"]


def read_csv(path):
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def test_violations_csv_exists():
    assert os.path.isfile(CSV_PATH), f"The expected output file {CSV_PATH} does not exist."


def test_violations_csv_contents():
    expected_rows = [
        HEADER,
        ["2023-10-01T10:05:00Z", "Charlie", "Engineering", "200", "WRITE"],
        ["2023-10-01T10:10:00Z", "Alice", "Engineering", "300", "READ"],
    ]

    assert os.path.isfile(CSV_PATH), f"The expected output file {CSV_PATH} does not exist."
    actual_rows = read_csv(CSV_PATH)
    assert len(actual_rows) > 0, f"The file {CSV_PATH} is empty."
    assert actual_rows[0] == expected_rows[0], (
        f"Header mismatch in {CSV_PATH}. Expected: {expected_rows[0]}, Got: {actual_rows[0]}"
    )
    assert actual_rows == expected_rows, (
        f"Content mismatch in {CSV_PATH}. Expected {expected_rows}, but got {actual_rows}."
    )


def test_c_source_uses_sqlite_and_join_and_compiles():
    assert os.path.isfile(SOURCE_PATH), f"Required C source {SOURCE_PATH} does not exist."
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must be a regular source file."

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", " ", source, flags=re.S)
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", without_comments), (
        "audit.c must include sqlite3.h"
    )
    assert re.search(r"\bsqlite3_[A-Za-z0-9_]+\b", without_comments), (
        "audit.c must use the SQLite C API"
    )
    assert re.search(r"\bSELECT\b", without_comments, flags=re.I), (
        "audit.c must contain a SQL SELECT query"
    )
    assert len(re.findall(r"\bJOIN\b", without_comments, flags=re.I)) >= 2, (
        "audit.c must use a multi-table JOIN to cross-reference users, departments, and permissions"
    )

    result = subprocess.run(
        ["gcc", "-o", BINARY_PATH, SOURCE_PATH, "-lsqlite3"],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"audit.c did not compile:\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), (
        "Compilation did not produce an executable"
    )


def install_fixture(db_bytes_path, log_text):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    shutil.copyfile(db_bytes_path, DB_PATH)
    with open(LOG_PATH, "w", encoding="utf-8") as f:
        f.write(log_text)
    os.chmod(DB_PATH, 0o666)
    os.chmod(LOG_PATH, 0o666)


def run_with_jq(jq_filter):
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass

    jq_proc = subprocess.Popen(
        ["jq", "-r", jq_filter, LOG_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=HOME,
    )
    try:
        audit_proc = subprocess.run(
            [BINARY_PATH],
            stdin=jq_proc.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=HOME,
            timeout=10,
        )
        jq_proc.stdout.close()
        jq_stderr = jq_proc.stderr.read()
        jq_return = jq_proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        jq_proc.kill()
        jq_proc.wait()
        return False, "execution timed out"

    if jq_return != 0:
        return False, "jq failed: " + jq_stderr.decode("utf-8", errors="replace")
    if audit_proc.returncode != 0:
        return False, "program failed: " + audit_proc.stderr.decode("utf-8", errors="replace")
    if not os.path.isfile(CSV_PATH):
        return False, "program did not create violations.csv"
    return True, ""


def test_compiled_program_on_unseen_data_via_jq_pipe():
    assert os.path.isfile(BINARY_PATH), "The compiled test executable is missing"

    token = secrets.token_hex(4)
    d1, d2 = 1000 + secrets.randbelow(500), 2000 + secrets.randbelow(500)
    r1, r2, r3, r4 = [5000 + secrets.randbelow(500) + i * 1000 for i in range(4)]
    departments = [(d1, "Platform_" + token), (d2, "Legal_" + token)]
    users = [
        (11, "Ava_" + token, d1),
        (22, "Noah_" + token, d1),
        (33, "Mia_" + token, d2),
    ]
    permissions = [
        (d1, r1, 1, 1),
        (d1, r2, 1, 0),
        (d2, r2, 0, 1),
        (d2, r3, 1, 1),
    ]
    logs = [
        {"timestamp": f"2026-08-01T09:00:01Z-{token}", "user_id": 11, "resource_id": r1, "action": "READ"},
        {"timestamp": f"2026-08-01T09:00:02Z-{token}", "user_id": 22, "resource_id": r2, "action": "WRITE"},
        {"timestamp": f"2026-08-01T09:00:03Z-{token}", "user_id": 33, "resource_id": r2, "action": "READ"},
        {"timestamp": f"2026-08-01T09:00:04Z-{token}", "user_id": 11, "resource_id": r3, "action": "READ"},
        {"timestamp": f"2026-08-01T09:00:05Z-{token}", "user_id": 33, "resource_id": r3, "action": "WRITE"},
        {"timestamp": f"2026-08-01T09:00:06Z-{token}", "user_id": 22, "resource_id": r4, "action": "WRITE"},
        {"timestamp": f"2026-08-01T09:00:07Z-{token}", "user_id": 33, "resource_id": r2, "action": "WRITE"},
        {"timestamp": f"2026-08-01T09:00:08Z-{token}", "user_id": 11, "resource_id": r2, "action": "READ"},
    ]

    user_map = {uid: (name, dept) for uid, name, dept in users}
    dept_map = dict(departments)
    perm_map = {(dept, resource): (can_read, can_write)
                for dept, resource, can_read, can_write in permissions}
    expected = [HEADER]
    for event in logs:
        user_name, dept = user_map[event["user_id"]]
        permission = perm_map.get((dept, event["resource_id"]))
        allowed = permission is not None and (
            permission[0] == 1 if event["action"] == "READ" else permission[1] == 1
        )
        if not allowed:
            expected.append([
                event["timestamp"], user_name, dept_map[dept],
                str(event["resource_id"]), event["action"],
            ])

    original = {}
    for path in (DB_PATH, LOG_PATH, CSV_PATH):
        original[path] = open(path, "rb").read() if os.path.exists(path) else None

    import json
    with tempfile.TemporaryDirectory() as td:
        fixture_db = os.path.join(td, "fixture.db")
        con = sqlite3.connect(fixture_db)
        con.executescript("""
            CREATE TABLE departments(id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER);
            CREATE TABLE permissions(dept_id INTEGER, resource_id INTEGER, can_read INTEGER, can_write INTEGER);
        """)
        con.executemany("INSERT INTO departments VALUES (?, ?)", departments)
        con.executemany("INSERT INTO users VALUES (?, ?, ?)", users)
        con.executemany("INSERT INTO permissions VALUES (?, ?, ?, ?)", permissions)
        con.commit()
        con.close()
        log_text = json.dumps(logs)

        filters = [
            '.[] | [.timestamp, (.user_id|tostring), (.resource_id|tostring), .action] | @tsv',
            '.[] | [.timestamp, (.user_id|tostring), (.resource_id|tostring), .action] | join(",")',
            '.[] | [.timestamp, (.user_id|tostring), (.resource_id|tostring), .action] | join(" ")',
            '.[] | [.timestamp, (.user_id|tostring), (.resource_id|tostring), .action] | join("|")',
            '.[] | .timestamp, .user_id, .resource_id, .action',
        ]

        failures = []
        matched = False
        try:
            for jq_filter in filters:
                install_fixture(fixture_db, log_text)
                ok, detail = run_with_jq(jq_filter)
                if not ok:
                    failures.append(detail)
                    continue
                try:
                    actual = read_csv(CSV_PATH)
                except Exception as exc:
                    failures.append(f"invalid CSV: {exc}")
                    continue
                if actual == expected:
                    matched = True
                    break
                failures.append(f"wrong output: {actual!r}")
        finally:
            for suffix in ("-wal", "-shm"):
                try:
                    os.remove(DB_PATH + suffix)
                except FileNotFoundError:
                    pass
            for path, data in original.items():
                if data is None:
                    try:
                        os.remove(path)
                    except FileNotFoundError:
                        pass
                else:
                    with open(path, "wb") as f:
                        f.write(data)

    assert matched, (
        "The compiled C program did not correctly process unseen logs piped from jq "
        "and query the unseen SQLite data. Attempts: " + "; ".join(failures)
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
