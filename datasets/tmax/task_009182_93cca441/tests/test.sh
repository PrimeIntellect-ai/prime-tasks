#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

AUDIT_SCRIPT = '/home/user/audit.py'
CSV_PATH = '/home/user/audit_results.csv'
DB_PATH = '/home/user/audit.db'


def run_audit():
    trace_fd, trace_path = tempfile.mkstemp(prefix='audit_sql_', suffix='.log')
    os.close(trace_fd)
    runner = r'''
import os
import runpy
import sqlite3 as real_sqlite3
import sys
import types

trace_path = os.environ['AUDIT_TRACE_PATH']
proxy = types.ModuleType('sqlite3')
proxy.__dict__.update(real_sqlite3.__dict__)

def traced_connect(*args, **kwargs):
    conn = real_sqlite3.connect(*args, **kwargs)
    def record(statement):
        with open(trace_path, 'a', encoding='utf-8') as out:
            out.write(statement.replace('\\n', ' ') + '\\n')
    conn.set_trace_callback(record)
    return conn

proxy.connect = traced_connect
sys.modules['sqlite3'] = proxy
runpy.run_path('/home/user/audit.py', run_name='__main__')
'''
    env = os.environ.copy()
    env['AUDIT_TRACE_PATH'] = trace_path
    try:
        result = subprocess.run(
            [sys.executable, '-c', runner],
            cwd='/home/user', env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            f'audit.py failed with exit code {result.returncode}.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        with open(trace_path, encoding='utf-8') as f:
            statements = f.read().splitlines()
    finally:
        if os.path.exists(trace_path):
            os.remove(trace_path)

    recursive_queries = [
        statement for statement in statements
        if re.search(r'\bWITH\s+RECURSIVE\b', statement, re.IGNORECASE)
    ]
    assert recursive_queries, 'audit.py did not execute a WITH RECURSIVE query.'
    assert any(
        all(re.search(r'\b' + table + r'\b', query, re.IGNORECASE)
            for table in ('departments', 'employees', 'access_logs'))
        for query in recursive_queries
    ), 'The executed recursive query must combine departments, employees, and access_logs.'


def read_csv():
    assert os.path.exists(CSV_PATH), f'File {CSV_PATH} is missing.'
    assert os.path.isfile(CSV_PATH), f'{CSV_PATH} is not a file.'
    with open(CSV_PATH, 'r', newline='') as f:
        return list(csv.reader(f))


def derived_expected_rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        departments = conn.execute(
            'SELECT dept_id, name, parent_dept_id FROM departments'
        ).fetchall()
        employees = {
            emp_id: (name, dept_id)
            for emp_id, name, dept_id in conn.execute(
                'SELECT emp_id, name, dept_id FROM employees'
            )
        }
        included = {dept_id for dept_id, name, _ in departments if name == 'Finance'}
        changed = True
        while changed:
            changed = False
            for dept_id, _, parent_id in departments:
                if parent_id in included and dept_id not in included:
                    included.add(dept_id)
                    changed = True
        dept_names = {dept_id: name for dept_id, name, _ in departments}
        rows = []
        for emp_id, access_time, resource in conn.execute(
            'SELECT emp_id, access_time, resource FROM access_logs'
        ):
            employee = employees.get(emp_id)
            if employee and employee[1] in included:
                rows.append([
                    employee[0], dept_names[employee[1]], access_time, resource
                ])
        rows.sort(key=lambda row: row[2])
        return [['EmployeeName', 'DepartmentName', 'AccessTime', 'Resource']] + rows
    finally:
        conn.close()


def test_audit_script_and_results_csv():
    assert os.path.exists(AUDIT_SCRIPT), f'File {AUDIT_SCRIPT} is missing.'
    assert os.path.isfile(AUDIT_SCRIPT), f'{AUDIT_SCRIPT} is not a file.'
    with open(AUDIT_SCRIPT, encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=AUDIT_SCRIPT)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split('.')[0])
    assert 'sqlite3' in imported, 'audit.py must use the standard sqlite3 module.'
    assert 'csv' in imported, 'audit.py must use the standard csv module.'

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    run_audit()

    expected_rows = [
        ['EmployeeName', 'DepartmentName', 'AccessTime', 'Resource'],
        ['Alice', 'Finance', '2023-10-01 09:00:00', 'ServerA'],
        ['Bob', 'Payroll', '2023-10-01 09:15:00', 'ServerB'],
        ['Charlie', 'Accounts Payable', '2023-10-01 09:30:00', 'ServerC'],
        ['Alice', 'Finance', '2023-10-01 10:00:00', 'ServerA']
    ]
    actual_rows = read_csv()
    assert actual_rows == expected_rows, (
        f'CSV content does not match expected output.\n'
        f'Expected: {expected_rows}\nActual: {actual_rows}'
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript("""
            INSERT INTO departments VALUES (6, 'Treasury', 1);
            INSERT INTO departments VALUES (7, 'Cash Operations', 6);
            INSERT INTO departments VALUES (8, 'Unrelated Child', 4);
            INSERT INTO employees VALUES (105, 'Eve', 7);
            INSERT INTO employees VALUES (106, 'Frank', 8);
            INSERT INTO access_logs VALUES (1006, 105, '2023-10-01 09:20:00', 'Vault');
            INSERT INTO access_logs VALUES (1007, 106, '2023-10-01 09:25:00', 'Decoy');
            INSERT INTO access_logs VALUES (1008, 105, '2023-10-01 10:30:00', 'Ledger');
        """)
        conn.commit()
    finally:
        conn.close()

    expected_dynamic = derived_expected_rows()
    os.remove(CSV_PATH)
    run_audit()
    actual_dynamic = read_csv()
    assert actual_dynamic == expected_dynamic, (
        'audit.py did not dynamically follow the deeper department hierarchy, '
        'join logs to the correct employees/departments, or sort by AccessTime.\n'
        f'Expected: {expected_dynamic}\nActual: {actual_dynamic}'
    )


def test_optimize_sql():
    sql_path = '/home/user/optimize.sql'
    assert os.path.exists(sql_path), f'File {sql_path} is missing.'
    assert os.path.isfile(sql_path), f'{sql_path} is not a file.'

    with open(sql_path, 'r') as f:
        content = f.read().strip()

    normalized_content = re.sub(r'\s+', ' ', content).lower()
    assert 'create index' in normalized_content, "Missing 'CREATE INDEX' in SQL file."
    assert 'idx_access_logs_emp_id' in normalized_content, "Missing correct index name 'idx_access_logs_emp_id'."
    assert 'on access_logs' in normalized_content, "Missing 'ON access_logs' in SQL file."
    assert '(emp_id)' in normalized_content.replace(' ', ''), "Missing '(emp_id)' in SQL file."

    fd, copied_db = tempfile.mkstemp(prefix='optimize_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, copied_db)
    conn = sqlite3.connect(copied_db)
    try:
        conn.execute('DROP INDEX IF EXISTS idx_access_logs_emp_id')
        conn.commit()
        conn.executescript(content)
        index_rows = conn.execute("PRAGMA index_list('access_logs')").fetchall()
        assert any(row[1] == 'idx_access_logs_emp_id' for row in index_rows), (
            'Executing optimize.sql did not create idx_access_logs_emp_id on access_logs.'
        )
        columns = conn.execute(
            "PRAGMA index_info('idx_access_logs_emp_id')"
        ).fetchall()
        assert [row[2] for row in columns] == ['emp_id'], (
            'idx_access_logs_emp_id must index exactly the emp_id column.'
        )
    finally:
        conn.close()
        os.remove(copied_db)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
