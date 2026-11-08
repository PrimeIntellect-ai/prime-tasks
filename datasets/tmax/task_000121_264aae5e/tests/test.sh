#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid
import pytest

SOURCE_PATH = "/home/user/audit_tool.c"
EXE_PATH = "/home/user/audit_tool"
REPORT_PATH = "/home/user/compliance_report.json"
DB_PATH = "/home/user/audit.db"


def get_expected_roles(db_path, username):
    """Derive the expected roles for a given user directly from the database."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    WITH RECURSIVE user_role_hierarchy AS (
        SELECT r.id, r.role_name
        FROM users u
        JOIN user_roles ur ON u.id = ur.user_id
        JOIN roles r ON ur.role_id = r.id
        WHERE u.username = ?

        UNION

        SELECT r.id, r.role_name
        FROM user_role_hierarchy urh
        JOIN role_inheritance ri ON urh.id = ri.role_id
        JOIN roles r ON ri.inherits_role_id = r.id
    )
    SELECT DISTINCT role_name FROM user_role_hierarchy ORDER BY role_name;
    """
    cursor.execute(query, (username,))
    roles = [row[0] for row in cursor.fetchall()]
    conn.close()
    return roles


def read_report():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")
    return raw, data


def run_and_check(executable, username):
    result = subprocess.run(
        [executable, username], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} failed for user {username!r}: {result.stderr}"
    )
    raw, data = read_report()
    expected = get_expected_roles(DB_PATH, username)
    assert data == expected, (
        f"Tool output for {username!r} is incorrect. Expected {expected}, found {data}."
    )
    canonical = json.dumps(expected)
    assert raw in (canonical, canonical + "\n"), (
        "The report must contain only a strictly formatted JSON array."
    )


def test_source_uses_recursive_cte_and_compiles():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    source = open(SOURCE_PATH, "r", encoding="utf-8").read()

    # Inspect C string literals rather than comments, so merely mentioning the
    # required SQL in a comment is not sufficient.
    literals = re.findall(r'"(?:\\.|[^"\\])*"', source, flags=re.S)
    decoded = []
    for literal in literals:
        try:
            decoded.append(ast.literal_eval(literal))
        except (SyntaxError, ValueError):
            pass
    string_text = " ".join(decoded)
    assert re.search(r"\bWITH\s+RECURSIVE\b", string_text, re.I), \
        "The C program's SQL must use WITH RECURSIVE."
    for required in ("user_roles", "role_inheritance", "roles"):
        assert re.search(rf"\b{required}\b", string_text, re.I), \
            f"The recursive SQL must query {required}."
    assert re.search(r"\bUNION(?:\s+ALL)?\b", string_text, re.I), \
        "The recursive CTE must contain a recursive UNION."
    assert "sqlite3_prepare" in source, "The program must prepare and execute its SQL query."

    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-lsqlite3", "-o", "/tmp/audit_tool_from_source"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"The submitted C source does not compile: {result.stderr}"


def test_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} is missing. Did you compile the C program?"
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted audit_tool must be a compiled executable."


def test_compliance_report_content():
    """Test that the compliance report contains the correct JSON data."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing. Did you run the tool?"
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of strings."
    expected_roles = get_expected_roles(DB_PATH, "charlie")
    assert data == expected_roles, (
        f"The roles in {REPORT_PATH} do not match the expected hierarchy for 'charlie'.\n"
        f"Expected: {expected_roles}\nFound: {data}"
    )


def test_tools_execute_and_resolve_unseen_hierarchy():
    """Exercise both the submitted binary and compiled source on derived inputs."""
    fd, backup = tempfile.mkstemp(prefix="audit-db-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup)
    try:
        nonce = uuid.uuid4().hex[:10]
        username = "verification_user_" + nonce
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        next_user = cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM users").fetchone()[0]
        first_role = cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM roles").fetchone()[0]
        role_names = [
            "z_top_" + nonce,
            "m_middle_" + nonce,
            "a_leaf_" + nonce,
            "b_branch_" + nonce,
        ]
        cur.execute("INSERT INTO users(id, username) VALUES (?, ?)", (next_user, username))
        cur.executemany(
            "INSERT INTO roles(id, role_name) VALUES (?, ?)",
            [(first_role + i, name) for i, name in enumerate(role_names)]
        )
        cur.execute("INSERT INTO user_roles(user_id, role_id) VALUES (?, ?)",
                    (next_user, first_role))
        cur.executemany(
            "INSERT INTO role_inheritance(role_id, inherits_role_id) VALUES (?, ?)",
            [
                (first_role, first_role + 1),
                (first_role + 1, first_role + 2),
                (first_role, first_role + 3),
            ]
        )
        conn.commit()
        conn.close()

        for executable in (EXE_PATH, "/tmp/audit_tool_from_source"):
            run_and_check(executable, username)
            run_and_check(executable, "alice")
            run_and_check(executable, "bob")
    finally:
        shutil.copy2(backup, DB_PATH)
        os.unlink(backup)

    # Leave the required final artifact as Charlie's report.
    run_and_check(EXE_PATH, "charlie")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
