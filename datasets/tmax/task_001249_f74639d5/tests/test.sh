#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

import pytest

REPORT_PATH = "/home/user/fixed_audit_report.csv"
SCRIPT_PATH = "/home/user/generate_audit.sh"
DB_PATH = "/home/user/compliance.db"

EXPECTED_LINES = [
    "Alice,CI-CD",
    "Alice,Prod-DB",
    "Alice,Wiki",
    "Bob,CI-CD",
    "Bob,Wiki",
    "Charlie,Wiki",
]


def run_script():
    assert os.path.isfile(SCRIPT_PATH), f"The script file {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."
    result = subprocess.run(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_nonempty_lines():
    assert os.path.isfile(REPORT_PATH), f"The expected output file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r", newline="") as f:
        return [line.strip() for line in f if line.strip()]


def read_csv_rows():
    assert os.path.isfile(REPORT_PATH), f"The expected output file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert all(len(row) == 2 for row in rows), "Every CSV row must contain exactly two columns."
    return [tuple(row) for row in rows]


def test_fixed_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The expected output file {REPORT_PATH} does not exist."


def test_fixed_audit_report_contents():
    lines = read_nonempty_lines()
    assert lines == EXPECTED_LINES, (
        f"The contents of {REPORT_PATH} do not match the expected correct output.\n"
        f"Expected:\n{EXPECTED_LINES}\nGot:\n{lines}"
    )


def test_generate_audit_script_modified():
    assert os.path.isfile(SCRIPT_PATH), f"The script file {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    original_flawed_where = "WHERE u.id = ur.user_id;"
    original_flawed_from = "FROM users u, systems s, user_roles ur, role_systems rs"
    is_fixed = (
        original_flawed_from not in content
        or original_flawed_where not in content
        or "JOIN" in content.upper()
    )
    assert is_fixed, f"The script {SCRIPT_PATH} still appears to contain the original flawed cross join query."
    assert "sqlite3" in content, f"The script {SCRIPT_PATH} must execute its query using sqlite3."


def test_script_generates_original_report():
    run_script()
    lines = read_nonempty_lines()
    assert lines == EXPECTED_LINES, (
        f"Executing {SCRIPT_PATH} did not generate the expected report.\n"
        f"Expected:\n{EXPECTED_LINES}\nGot:\n{lines}"
    )


def test_script_traverses_user_role_system_graph():
    token = uuid.uuid4().hex
    backup_fd, backup_path = tempfile.mkstemp(prefix="compliance-backup-", suffix=".db", dir="/tmp")
    os.close(backup_fd)
    os.unlink(backup_path)

    source = sqlite3.connect(DB_PATH)
    backup = sqlite3.connect(backup_path)
    source.backup(backup)
    source.close()
    backup.close()

    dynamic_fd, dynamic_path = tempfile.mkstemp(prefix="compliance-dynamic-", suffix=".db", dir="/home/user")
    os.close(dynamic_fd)
    os.unlink(dynamic_path)

    try:
        conn = sqlite3.connect(dynamic_path)
        conn.executescript("""
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE roles (id INTEGER PRIMARY KEY, role_name TEXT);
            CREATE TABLE systems (id INTEGER PRIMARY KEY, sys_name TEXT);
            CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
            CREATE TABLE role_systems (role_id INTEGER, system_id INTEGER);
        """)

        users = [
            (11, f"Delta-{token}"),
            (27, f"Alpha-{token}"),
            (42, f"Charlie-{token}"),
            (88, f"NoAccess-{token}"),
        ]
        roles = [(5, "R5"), (13, "R13"), (31, "R31"), (49, "Unused")]
        systems = [
            (7, f"Zulu-{token}"),
            (19, f"Beta-{token}"),
            (55, f"Omega-{token}"),
            (91, f"Gamma-{token}"),
        ]
        conn.executemany("INSERT INTO users VALUES (?, ?)", users)
        conn.executemany("INSERT INTO roles VALUES (?, ?)", roles)
        conn.executemany("INSERT INTO systems VALUES (?, ?)", systems)
        conn.executemany("INSERT INTO user_roles VALUES (?, ?)", [
            (11, 5), (11, 13), (27, 13), (27, 5), (42, 31), (88, 49)
        ])
        conn.executemany("INSERT INTO role_systems VALUES (?, ?)", [
            (5, 19), (5, 7), (13, 55), (31, 91)
        ])
        conn.commit()

        expected = conn.execute("""
            SELECT u.name, s.sys_name
            FROM users AS u
            JOIN user_roles AS ur ON ur.user_id = u.id
            JOIN role_systems AS rs ON rs.role_id = ur.role_id
            JOIN systems AS s ON s.id = rs.system_id
            ORDER BY u.name ASC, s.sys_name ASC
        """).fetchall()
        conn.close()

        os.chmod(dynamic_path, 0o666)
        os.replace(dynamic_path, DB_PATH)
        run_script()
        actual = read_csv_rows()
        assert actual == expected, (
            "The executed script did not derive access through User -> Role -> System, "
            "or did not emit exactly two correctly sorted CSV columns.\n"
            f"Expected: {expected}\nGot: {actual}"
        )
    finally:
        if os.path.exists(dynamic_path):
            os.unlink(dynamic_path)
        if os.path.exists(backup_path):
            os.replace(backup_path, DB_PATH)
            os.chmod(DB_PATH, 0o666)
        if os.path.isfile(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
            subprocess.run([SCRIPT_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
