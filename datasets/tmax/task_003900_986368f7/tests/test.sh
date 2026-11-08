#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

SCRIPT_PATH = "/home/user/audit_query.py"
DB_PATH = "/home/user/audit.db"
REPORT_PATH = "/home/user/report.json"
EXPECTED_KEYS = {"name", "resource", "access_timestamp", "ip_address", "auth_timestamp"}


def run_script(resource, ip_prefix, limit, offset):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    cmd = [
        sys.executable,
        SCRIPT_PATH,
        "--resource", resource,
        "--ip-prefix", ip_prefix,
        "--limit", str(limit),
        "--offset", str(offset),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f"Script failed to execute. Return code: {result.returncode}, "
        f"stderr: {result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), (
        f"Report file was not created at {REPORT_PATH} after script execution."
    )

    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Report file {REPORT_PATH} does not contain valid JSON."

    assert isinstance(report_data, list), "Report JSON must be a JSON array (list) of objects."
    return report_data


def expected_from_db(resource, ip_prefix, limit, offset):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT e.name, ac.resource, ac.access_timestamp, au.ip_address, au.auth_timestamp
        FROM employees e
        JOIN access_logs ac ON e.id = ac.emp_id
        JOIN auth_logs au ON e.id = au.emp_id
        WHERE e.department = 'Engineering'
          AND ac.resource = ?
          AND au.ip_address LIKE ?
        ORDER BY ac.access_timestamp DESC, au.auth_timestamp DESC, e.name ASC
        LIMIT ? OFFSET ?
        """,
        (resource, ip_prefix + "%", limit, offset),
    )
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows


def assert_report(report_data, expected_data):
    assert len(report_data) == len(expected_data), (
        f"Expected {len(expected_data)} records in the JSON report, "
        f"but got {len(report_data)}."
    )
    for i, (actual, expected) in enumerate(zip(report_data, expected_data)):
        assert isinstance(actual, dict), f"Row {i} is not a JSON object."
        actual_keys = set(actual.keys())
        assert actual_keys == EXPECTED_KEYS, (
            f"Row {i} has incorrect keys. Expected {EXPECTED_KEYS}, got {actual_keys}"
        )
        assert actual["name"] == expected["name"], f"Row {i}: incorrect name"
        assert actual["resource"] == expected["resource"], f"Row {i}: incorrect resource"
        assert actual["access_timestamp"] == expected["access_timestamp"], f"Row {i}: incorrect access_timestamp"
        assert actual["ip_address"] == expected["ip_address"], f"Row {i}: incorrect ip_address"
        assert actual["auth_timestamp"] == expected["auth_timestamp"], f"Row {i}: incorrect auth_timestamp"


def test_script_exists_and_structure():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Script path is not a regular file: {SCRIPT_PATH}"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
    assert "argparse" in imported, "The script must use the standard argparse module."
    assert "sqlite3" in imported, "The script must use the standard sqlite3 module."

    required_flags = {"--resource", "--ip-prefix", "--limit", "--offset"}
    declared_flags = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "add_argument":
            for arg in node.args:
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    declared_flags.add(arg.value)
    assert required_flags <= declared_flags, f"Missing argparse options: {required_flags - declared_flags}"

    execute_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "execute"
    ]
    assert len(execute_calls) == 1, "The script must execute a single SQL query."
    execute_call = execute_calls[0]
    has_parameters = len(execute_call.args) >= 2 or any(
        keyword.arg in {"parameters", "params"} for keyword in execute_call.keywords
    )
    assert has_parameters, "The SQL query must pass values separately as parameters."


def test_original_database_case():
    report_data = run_script("/etc/shadow", "192.168.", 2, 1)
    expected_data = expected_from_db("/etc/shadow", "192.168.", 2, 1)
    assert_report(report_data, expected_data)


def create_random_database(path, token):
    resource_one = f"/restricted/{token}'records"
    resource_two = f"/alternate/{token}"
    prefix_one = f"172.{int(token[:2], 16)}."
    prefix_two = f"q'{token[:8]}"

    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
    cur.execute("CREATE TABLE access_logs (id INTEGER PRIMARY KEY, emp_id INTEGER, resource TEXT, access_timestamp DATETIME)")
    cur.execute("CREATE TABLE auth_logs (id INTEGER PRIMARY KEY, emp_id INTEGER, ip_address TEXT, auth_timestamp DATETIME)")

    cur.executemany("INSERT INTO employees VALUES (?, ?, ?)", [
        (1, f"Zed-{token[:6]}", "Engineering"),
        (2, f"Amy-{token[6:12]}", "Engineering"),
        (3, f"HR-{token[12:18]}", "HR"),
        (4, f"Moe-{token[18:24]}", "Engineering"),
        (5, f"Near-{token[24:30]}", "engineering"),
    ])
    cur.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?)", [
        (1, 1, resource_one, "2041-04-01 10:00:00"),
        (2, 2, resource_one, "2041-04-03 12:00:00"),
        (3, 3, resource_one, "2041-04-04 13:00:00"),
        (4, 4, resource_one, "2041-04-03 12:00:00"),
        (5, 1, resource_two, "2041-04-05 14:00:00"),
        (6, 5, resource_one, "2041-04-06 15:00:00"),
    ])
    cur.executemany("INSERT INTO auth_logs VALUES (?, ?, ?, ?)", [
        (1, 1, prefix_one + "10", "2041-04-01 09:00:00"),
        (2, 1, prefix_one + "11", "2041-04-01 11:00:00"),
        (3, 2, prefix_one + "20", "2041-04-03 10:00:00"),
        (4, 2, "10.10.10.20", "2041-04-03 13:00:00"),
        (5, 3, prefix_one + "30", "2041-04-04 12:00:00"),
        (6, 4, prefix_one + "40", "2041-04-03 10:00:00"),
        (7, 1, prefix_two + "-host", "2041-04-05 13:30:00"),
        (8, 5, prefix_one + "50", "2041-04-06 14:30:00"),
    ])
    conn.commit()
    conn.close()
    return resource_one, resource_two, prefix_one, prefix_two


def test_parameterization_and_alternate_inputs():
    token = uuid.uuid4().hex
    fd, backup_path = tempfile.mkstemp(prefix="audit-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    replacement_path = DB_PATH + ".verifier-new"
    try:
        if os.path.exists(replacement_path):
            os.remove(replacement_path)
        resource_one, resource_two, prefix_one, prefix_two = create_random_database(replacement_path, token)
        os.replace(replacement_path, DB_PATH)

        cases = [
            (resource_one, prefix_one, 3, 0),
            (resource_one, prefix_one, 2, 1),
            (resource_two, prefix_two, 10, 0),
            (resource_one + "-missing", prefix_one, 5, 0),
        ]
        for resource, prefix, limit, offset in cases:
            actual = run_script(resource, prefix, limit, offset)
            expected = expected_from_db(resource, prefix, limit, offset)
            assert_report(actual, expected)
    finally:
        if os.path.exists(replacement_path):
            os.remove(replacement_path)
        os.replace(backup_path, DB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
