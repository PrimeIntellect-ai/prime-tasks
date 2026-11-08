#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'LAUNCHER_EOF' > /tmp/run_audit_instrumented.py
import json
import runpy
import sqlite3
import sys

script_path, trace_path = sys.argv[1], sys.argv[2]
real_connect = sqlite3.connect
statements = []

def traced_connect(*args, **kwargs):
    conn = real_connect(*args, **kwargs)
    conn.set_trace_callback(statements.append)
    return conn

sqlite3.connect = traced_connect
try:
    runpy.run_path(script_path, run_name='__main__')
finally:
    with open(trace_path, 'w') as f:
        json.dump(statements, f)
LAUNCHER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import sys
import pytest

DB_PATH = '/home/user/audit.db'
REPORT_PATH = '/home/user/compliance_report.json'
SCRIPT_PATH = '/home/user/audit_report.py'
PLAN_PATH = '/home/user/query_plan.txt'
TRACE_PATH = '/tmp/audit_sql_trace.json'
LAUNCHER_PATH = '/tmp/run_audit_instrumented.py'

UNAUTHORIZED_SQL = """
    WITH RECURSIVE
    management_chain AS (
        SELECT id as owner_id, manager_id as boss_id FROM employees WHERE manager_id IS NOT NULL
        UNION ALL
        SELECT mc.owner_id, e.manager_id
        FROM management_chain mc
        JOIN employees e ON mc.boss_id = e.id
        WHERE e.manager_id IS NOT NULL
    )
    SELECT a.id
    FROM access_logs a
    LEFT JOIN management_chain mc ON a.resource_owner_id = mc.owner_id AND a.employee_id = mc.boss_id
    WHERE a.employee_id != a.resource_owner_id
    AND mc.boss_id IS NULL
    ORDER BY a.id
"""

@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Remove one-off optimization artifacts so the submitted script must create them.
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")
    for (name,) in c.fetchall():
        c.execute('DROP INDEX ' + '"' + name.replace('"', '""') + '"')

    # Add data unknown when the image was built, ensuring the script really queries the DB.
    c.execute("SELECT COALESCE(MAX(id), 0) FROM employees")
    employee_id = c.fetchone()[0] + 10000
    c.execute("SELECT COALESCE(MAX(id), 0) FROM access_logs")
    first_log_id = c.fetchone()[0] + 1
    c.execute(
        "INSERT INTO employees(id, name, manager_id, permissions) VALUES (?, ?, NULL, ?)",
        (employee_id, 'Verifier Sentinel', json.dumps(['READ', 'APPROVE_FUNDS', 'REQUEST_FUNDS']))
    )
    rows = []
    for offset in range(6):
        rows.append((first_log_id + offset, employee_id, employee_id,
                     f'2023-02-01 0{offset}:00:00', 'READ'))
    rows.append((first_log_id + 6, employee_id, 1, '2023-02-01 06:00:00', 'READ'))
    c.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)", rows)
    conn.commit()
    conn.close()

    for path in (REPORT_PATH, PLAN_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [sys.executable, LAUNCHER_PATH, SCRIPT_PATH, TRACE_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180
    )
    assert result.returncode == 0, (
        f"audit_report.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_files_exist():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Report missing: {REPORT_PATH}"
    assert os.path.isfile(PLAN_PATH), f"Query plan missing: {PLAN_PATH}"


def test_script_executed_required_sql():
    assert os.path.isfile(TRACE_PATH), "No SQL execution trace was produced."
    with open(TRACE_PATH, 'r') as f:
        statements = json.load(f)
    normalized = [' '.join(sql.upper().split()) for sql in statements]

    assert any(re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', sql) for sql in normalized), \
        "audit_report.py did not execute a CREATE INDEX statement."
    assert any('EXPLAIN QUERY PLAN' in sql and 'ACCESS_LOGS' in sql and 'EMPLOYEES' in sql
               for sql in normalized), \
        "audit_report.py did not execute EXPLAIN QUERY PLAN for the unauthorized-access query."
    assert any('ACCESS_LOGS' in sql and 'EXPLAIN QUERY PLAN' not in sql for sql in normalized), \
        "audit_report.py did not execute a data query against access_logs."
    assert any('EMPLOYEES' in sql and 'EXPLAIN QUERY PLAN' not in sql for sql in normalized), \
        "audit_report.py did not execute a data query against employees."


def test_compliance_report_content():
    assert os.path.isfile(REPORT_PATH), "Report file does not exist."

    with open(REPORT_PATH, 'r') as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("compliance_report.json is not valid JSON.")

    required_keys = {"unauthorized_access_log_ids", "anomalous_employee_ids", "toxic_employee_ids"}
    assert set(agent_data.keys()) == required_keys, f"Report keys mismatch. Expected {required_keys}, got {set(agent_data.keys())}"

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # 1. Toxic
    c.execute("SELECT id FROM employees WHERE permissions LIKE '%APPROVE_FUNDS%' AND permissions LIKE '%REQUEST_FUNDS%' ORDER BY id")
    toxic = [r[0] for r in c.fetchall()]
    assert agent_data['toxic_employee_ids'] == toxic, "toxic_employee_ids do not match the expected output."

    # 2. Anomalous
    c.execute("""
        SELECT DISTINCT employee_id FROM (
            SELECT employee_id, count(*) OVER (
                PARTITION BY employee_id
                ORDER BY strftime('%s', timestamp)
                RANGE BETWEEN 259200 PRECEDING AND CURRENT ROW
            ) as cnt
            FROM access_logs
        ) WHERE cnt > 5 ORDER BY employee_id
    """)
    anomalous = [r[0] for r in c.fetchall()]
    assert agent_data['anomalous_employee_ids'] == anomalous, "anomalous_employee_ids do not match the expected output."

    # 3. Unauthorized
    c.execute(UNAUTHORIZED_SQL)
    unauth = [r[0] for r in c.fetchall()]
    assert agent_data['unauthorized_access_log_ids'] == unauth, "unauthorized_access_log_ids do not match the expected output."

    conn.close()


def test_database_optimized():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
    indexes = c.fetchall()

    assert len(indexes) > 0, "No custom indexes were created in the database to optimize the queries."

    relevant = False
    for name, table in indexes:
        c.execute('PRAGMA index_info(' + '"' + name.replace('"', '""') + '"' + ')')
        columns = [row[2].lower() for row in c.fetchall() if row[2] is not None]
        table = table.lower()
        if table == 'employees' and columns and columns[0] == 'manager_id':
            relevant = True
        if table == 'access_logs' and len(columns) >= 2:
            if columns[0:2] == ['employee_id', 'timestamp']:
                relevant = True
            if set(columns[0:2]) == {'resource_owner_id', 'employee_id'}:
                relevant = True
    conn.close()

    assert relevant, (
        "Custom indexes exist, but none is appropriate for the hierarchy, rolling-volume, "
        "or unauthorized-access queries."
    )


def test_query_plan_output():
    assert os.path.isfile(PLAN_PATH), "Query plan file does not exist."
    with open(PLAN_PATH, 'r') as f:
        content = f.read().strip()
    assert len(content) > 0, "query_plan.txt is empty."
    assert "SCAN" in content or "SEARCH" in content or "EXECUTE" in content, "query_plan.txt does not look like a valid EXPLAIN QUERY PLAN output."

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute('EXPLAIN QUERY PLAN ' + UNAUTHORIZED_SQL).fetchall()
    conn.close()
    expected_details = [str(row[3]) for row in rows]
    missing = [detail for detail in expected_details if detail not in content]
    assert not missing, (
        "query_plan.txt is not the actual EXPLAIN QUERY PLAN output for the "
        f"unauthorized-access query; missing plan rows: {missing}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
