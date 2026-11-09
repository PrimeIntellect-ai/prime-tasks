#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import runpy
import sqlite3
import uuid
import pytest

SCRIPT_PATH = '/home/user/audit_report.py'
DB_PATH = '/home/user/audit.db'
JSON_PATH = '/home/user/admin_audit.json'


def get_expected_results(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    query = """
    WITH RECURSIVE SuperAdminRoles AS (
        SELECT role_id
        FROM roles
        WHERE role_name = 'SuperAdmin'

        UNION ALL

        SELECT rh.role_id
        FROM role_hierarchy rh
        INNER JOIN SuperAdminRoles sar ON rh.inherits_role_id = sar.role_id
    )
    SELECT e.id AS emp_id, e.name
    FROM employees e
    INNER JOIN employee_roles er ON e.id = er.emp_id
    INNER JOIN SuperAdminRoles sar ON er.role_id = sar.role_id
    ORDER BY e.id ASC;
    """

    c.execute(query)
    results = [dict(row) for row in c.fetchall()]
    conn.close()
    return results


@pytest.fixture(scope='module', autouse=True)
def execute_report_on_extended_database():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."

    # Add data unknown to a precomputed report, including a two-level inherited
    # role and a negative control role.
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    superadmin = c.execute(
        "SELECT role_id FROM roles WHERE role_name = 'SuperAdmin'"
    ).fetchone()
    assert superadmin is not None, "The database has no SuperAdmin role."

    next_role = c.execute("SELECT COALESCE(MAX(role_id), 0) + 1 FROM roles").fetchone()[0]
    next_emp = c.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM employees").fetchone()[0]
    suffix = uuid.uuid4().hex

    c.executemany('INSERT INTO roles(role_id, role_name) VALUES (?, ?)', [
        (next_role, 'AuditParent_' + suffix),
        (next_role + 1, 'AuditChild_' + suffix),
        (next_role + 2, 'AuditNegative_' + suffix),
    ])
    c.executemany('INSERT INTO role_hierarchy(role_id, inherits_role_id) VALUES (?, ?)', [
        (next_role, superadmin[0]),
        (next_role + 1, next_role),
    ])
    c.executemany('INSERT INTO employees(id, name) VALUES (?, ?)', [
        (next_emp, 'DynamicDirect_' + suffix),
        (next_emp + 1, 'DynamicRecursive_' + suffix),
        (next_emp + 2, 'DynamicNegative_' + suffix),
    ])
    c.executemany('INSERT INTO employee_roles(emp_id, role_id) VALUES (?, ?)', [
        (next_emp, superadmin[0]),
        (next_emp + 1, next_role + 1),
        (next_emp + 2, next_role + 2),
    ])
    conn.commit()
    conn.close()

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    executed_sql = []
    original_connect = sqlite3.connect

    class TracingCursor(sqlite3.Cursor):
        def execute(self, sql, parameters=()):
            executed_sql.append(sql)
            return super().execute(sql, parameters)

        def executescript(self, sql_script):
            executed_sql.append(sql_script)
            return super().executescript(sql_script)

    class TracingConnection(sqlite3.Connection):
        def cursor(self, *args, **kwargs):
            kwargs.setdefault('factory', TracingCursor)
            return super().cursor(*args, **kwargs)

        def execute(self, sql, parameters=()):
            executed_sql.append(sql)
            return super().execute(sql, parameters)

        def executescript(self, sql_script):
            executed_sql.append(sql_script)
            return super().executescript(sql_script)

    def traced_connect(*args, **kwargs):
        kwargs.setdefault('factory', TracingConnection)
        return original_connect(*args, **kwargs)

    sqlite3.connect = traced_connect
    try:
        runpy.run_path(SCRIPT_PATH, run_name='__main__')
    finally:
        sqlite3.connect = original_connect

    required_tokens = ('WITH RECURSIVE', 'ROLE_HIERARCHY', 'EMPLOYEE_ROLES', 'EMPLOYEES')
    assert any(
        all(token in str(sql).upper() for token in required_tokens)
        for sql in executed_sql
    ), "The script did not execute the required recursive CTE and employee joins."


def test_json_output_exists_and_correct():
    json_path = '/home/user/admin_audit.json'
    db_path = '/home/user/audit.db'

    assert os.path.isfile(json_path), f"Expected JSON output file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    expected_data = get_expected_results(db_path)

    assert isinstance(actual_data, list), f"Expected JSON root to be a list, got {type(actual_data).__name__}."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Expected item at index {i} to be a dictionary."
        assert "emp_id" in actual, f"Missing 'emp_id' key in item at index {i}."
        assert "name" in actual, f"Missing 'name' key in item at index {i}."

        assert actual["emp_id"] == expected["emp_id"], f"Expected emp_id {expected['emp_id']} at index {i}, got {actual['emp_id']}."
        assert actual["name"] == expected["name"], f"Expected name '{expected['name']}' at index {i}, got '{actual['name']}'."


def test_script_uses_cte():
    script_path = '/home/user/audit_report.py'
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    with open(script_path, 'r') as f:
        content = f.read().upper()

    assert "WITH RECURSIVE" in content or "WITH " in content, "The script does not seem to use a Common Table Expression (CTE) as required."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
