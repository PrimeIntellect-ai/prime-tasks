#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

AUDIT_DIR = "/home/user/audit"
DB_PATH = "/home/user/audit.db"
LOG_PATH = "/home/user/violations.log"
SOURCE_PATH = os.path.join(AUDIT_DIR, "find_violations.go")
GO_MOD_PATH = os.path.join(AUDIT_DIR, "go.mod")


def run_program():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    result = subprocess.run(
        ["go", "run", "find_violations.go"],
        cwd=AUDIT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "go run find_violations.go failed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Expected file {LOG_PATH} does not exist."


def read_log():
    with open(LOG_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def drop_user_indexes(db_path):
    conn = sqlite3.connect(db_path)
    try:
        names = [row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        )]
        for name in names:
            conn.execute('DROP INDEX IF EXISTS "' + name.replace('"', '""') + '"')
        conn.commit()
    finally:
        conn.close()


def assert_required_indexes(db_path):
    conn = sqlite3.connect(db_path)
    try:
        indexes = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master WHERE type='index'"
        ).fetchall()
    finally:
        conn.close()
    user_indexes = [idx for idx in indexes if not idx[0].startswith("sqlite_")]
    tables_with_indexes = {idx[1] for idx in user_indexes}
    assert "group_hierarchy" in tables_with_indexes, "No index found on table 'group_hierarchy'."
    assert "group_members" in tables_with_indexes, "No index found on table 'group_members'."


def build_generated_fixture(path):
    token = secrets.token_hex(6)
    employees = [
        (201, f"Zara_{token}"),
        (202, f"Amy_{token}"),
        (203, f"Mona_{token}"),
        (204, f"Carl_{token}"),
        (205, f"Ned_{token}"),
        (206, f"Bea_{token}"),
        (207, f"Omar_{token}"),
    ]
    groups = [(gid, f"G{gid}_{token}") for gid in range(301, 308)]
    hierarchy = [
        (301, 302),
        (302, 303),
        (304, 305),
    ]
    policies = [
        (301, "FINANCIAL_RECORDS", "WRITE"),
        (304, "FINANCIAL_RECORDS", "ADMIN"),
        (306, "FINANCIAL_RECORDS", "READ"),
        (307, "OTHER_RESOURCE", "ADMIN"),
    ]
    memberships = [
        (201, 303),
        (202, 302),
        (203, 301),
        (204, 305),
        (205, 306),
        (206, 307),
        (207, 306),
        (207, 303),
    ]

    conn = sqlite3.connect(path)
    try:
        conn.executescript("""
            CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE groups (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE group_members (employee_id INTEGER, group_id INTEGER);
            CREATE TABLE group_hierarchy (parent_group_id INTEGER, child_group_id INTEGER);
            CREATE TABLE access_policies (group_id INTEGER, resource_name TEXT, access_level TEXT);
        """)
        conn.executemany("INSERT INTO employees VALUES (?, ?)", employees)
        conn.executemany("INSERT INTO groups VALUES (?, ?)", groups)
        conn.executemany("INSERT INTO group_hierarchy VALUES (?, ?)", hierarchy)
        conn.executemany("INSERT INTO access_policies VALUES (?, ?, ?)", policies)
        conn.executemany("INSERT INTO group_members VALUES (?, ?)", memberships)
        conn.commit()
    finally:
        conn.close()

    # Independently derive effective access by walking from each direct group to
    # all of its parents, rather than trusting a fixed expected output.
    names = dict(employees)
    parents = {}
    for parent, child in hierarchy:
        parents.setdefault(child, set()).add(parent)
    qualifying_groups = {
        group_id for group_id, resource, level in policies
        if resource == "FINANCIAL_RECORDS" and level in {"WRITE", "ADMIN"}
    }
    qualifying_employees = set()
    for employee_id, direct_group in memberships:
        stack = [direct_group]
        seen = set()
        while stack:
            group_id = stack.pop()
            if group_id in seen:
                continue
            seen.add(group_id)
            if group_id in qualifying_groups:
                qualifying_employees.add(employee_id)
            stack.extend(parents.get(group_id, ()))
    return sorted(names[eid] for eid in qualifying_employees)


def test_complete_go_solution():
    assert os.path.isfile(SOURCE_PATH), f"Expected Go program {SOURCE_PATH} does not exist."
    assert os.path.isfile(GO_MOD_PATH), f"Go module file {GO_MOD_PATH} does not exist."

    with open(GO_MOD_PATH, "r") as f:
        go_mod = f.read()
    assert "github.com/mattn/go-sqlite3" in go_mod, (
        "go.mod does not contain the required github.com/mattn/go-sqlite3 dependency."
    )

    with open(SOURCE_PATH, "r") as f:
        source = f.read()
    assert re.search(r'["`]database/sql["`]', source), "find_violations.go must import database/sql."
    assert re.search(r'["`]github\.com/mattn/go-sqlite3["`]', source), (
        "find_violations.go must import github.com/mattn/go-sqlite3."
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "find_violations.go does not contain the required recursive CTE."
    )

    deps = subprocess.run(
        ["go", "list", "-deps", "."], cwd=AUDIT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert deps.returncode == 0, f"Go package cannot be resolved:\n{deps.stderr}"
    dep_names = set(deps.stdout.splitlines())
    assert "database/sql" in dep_names, "The compiled Go program does not use database/sql."
    assert "github.com/mattn/go-sqlite3" in dep_names, (
        "The compiled Go program does not include github.com/mattn/go-sqlite3."
    )

    fd, backup_path = tempfile.mkstemp(prefix="audit-db-backup-")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        # Preserve the original output assertion, but require the submitted
        # program itself to recreate both indexes and produce the file.
        drop_user_indexes(DB_PATH)
        run_program()
        expected_names = ["Bob", "Charlie", "Dave", "Eve"]
        lines = read_log()
        assert lines == expected_names, (
            f"Expected {expected_names} in violations.log, but got {lines}."
        )
        assert_required_indexes(DB_PATH)

        # Replace the fixed database with an unpredictable graph and derive its
        # answer independently. This rejects fabricated fixed output.
        generated_fd, generated_path = tempfile.mkstemp(prefix="audit-generated-", suffix=".db")
        os.close(generated_fd)
        os.remove(generated_path)
        try:
            expected_generated = build_generated_fixture(generated_path)
            shutil.copy2(generated_path, DB_PATH)
            run_program()
            assert read_log() == expected_generated, (
                f"Program failed generated recursive-graph test; expected {expected_generated}, "
                f"got {read_log()}."
            )
            assert_required_indexes(DB_PATH)
        finally:
            if os.path.exists(generated_path):
                os.remove(generated_path)
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        # Leave the required deliverables in their expected final state.
        run_program()


PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
