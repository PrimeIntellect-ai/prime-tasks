#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import sys
import uuid
from collections import deque

SCRIPT = "/home/user/audit_path.py"
DB = "/home/user/audit.db"
OUTPUT = "/home/user/vulnerability_path.txt"


def run_script():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"audit_path.py failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The script did not create vulnerability_path.txt."


def read_output():
    with open(OUTPUT, "r") as f:
        return f.read()


def expected_path_from_database():
    conn = sqlite3.connect(DB)
    try:
        edges = {}
        for source, target in conn.execute("""
            SELECT e.name, s.name
            FROM employees e
            JOIN employee_roles er ON er.emp_id = e.id
            JOIN role_access ra ON ra.role_id = er.role_id
            JOIN systems s ON s.id = ra.system_id
        """):
            edges.setdefault(source, []).append(target)

        for source, target in conn.execute("""
            SELECT src.name, dst.name
            FROM system_connections sc
            JOIN systems src ON src.id = sc.source_id
            JOIN systems dst ON dst.id = sc.target_id
        """):
            edges.setdefault(source, []).append(target)
    finally:
        conn.close()

    queue = deque([("Eve", ["Eve"])])
    visited = {"Eve"}
    while queue:
        node, path = queue.popleft()
        if node == "Main_Ledger":
            return ",".join(path)
        for neighbor in edges.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, path + [neighbor]))
    raise AssertionError("Verifier-generated database unexpectedly has no path")


def create_database(case_number):
    if os.path.exists(DB):
        os.remove(DB)

    token = uuid.uuid4().hex[:10]
    base = 1000 + case_number * 100
    emp_id = 70 + case_number
    role_id = 900 + case_number
    a = f"Entry_{token}"
    b = f"Relay_{token}"
    c = f"Service_{token}"
    d = f"Gateway_{token}"

    conn = sqlite3.connect(DB)
    try:
        cdb = conn.cursor()
        cdb.execute("CREATE TABLE employees (id INTEGER, name TEXT)")
        cdb.execute("CREATE TABLE systems (id INTEGER, name TEXT, sensitivity TEXT)")
        cdb.execute("CREATE TABLE employee_roles (emp_id INTEGER, role_id INTEGER)")
        cdb.execute("CREATE TABLE role_access (role_id INTEGER, system_id INTEGER)")
        cdb.execute("CREATE TABLE system_connections (source_id INTEGER, target_id INTEGER)")
        cdb.executemany("INSERT INTO employees VALUES (?, ?)", [
            (emp_id, "Eve"), (emp_id + 1, "Alice")
        ])
        cdb.executemany("INSERT INTO systems VALUES (?, ?, ?)", [
            (base + 1, a, "Low"),
            (base + 2, b, "Medium"),
            (base + 3, c, "High"),
            (base + 4, "Main_Ledger", "Critical"),
            (base + 5, d, "High"),
        ])
        cdb.execute("INSERT INTO employee_roles VALUES (?, ?)", (emp_id, role_id))

        if case_number == 1:
            cdb.executemany("INSERT INTO role_access VALUES (?, ?)", [
                (role_id, base + 1), (role_id, base + 5)
            ])
            cdb.executemany("INSERT INTO system_connections VALUES (?, ?)", [
                (base + 1, base + 2),
                (base + 2, base + 4),
                (base + 5, base + 3),
                (base + 3, base + 2),
            ])
        else:
            cdb.execute("INSERT INTO role_access VALUES (?, ?)", (role_id, base + 3))
            cdb.executemany("INSERT INTO system_connections VALUES (?, ?)", [
                (base + 3, base + 5),
                (base + 5, base + 1),
                (base + 1, base + 4),
                (base + 2, base + 4),
            ])
        conn.commit()
    finally:
        conn.close()


def assert_exact_single_line(expected):
    raw = read_output()
    assert raw in (expected, expected + "\n"), (
        f"Expected a single line containing '{expected}', but got {raw!r}"
    )


def test_script_exists():
    """Test that the python script was created."""
    assert os.path.isfile(SCRIPT), "The script /home/user/audit_path.py was not found."


def test_script_executes_on_original_database():
    """Execute the submitted artifact rather than trusting a prewritten output."""
    run_script()


def test_output_file_exists():
    """Test that the output text file was created."""
    assert os.path.isfile(OUTPUT), "The output file /home/user/vulnerability_path.txt was not found."


def test_output_content():
    """Test that the output text file contains the correct shortest path."""
    with open(OUTPUT, "r") as f:
        content = f.read().strip()

    expected = "Eve,Dev_Server,Prod_App_Server,Main_Ledger"
    assert content == expected, f"Expected path '{expected}', but got '{content}'"
    assert_exact_single_line(expected)


def test_script_computes_paths_from_relational_data():
    backup = "/tmp/audit.db.verifier-backup"
    shutil.copy2(DB, backup)
    try:
        for case_number in (1, 2):
            create_database(case_number)
            expected = expected_path_from_database()
            run_script()
            assert_exact_single_line(expected)
    finally:
        shutil.copy2(backup, DB)
        os.remove(backup)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
