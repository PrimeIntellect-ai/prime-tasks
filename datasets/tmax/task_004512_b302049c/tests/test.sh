#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import sqlite3
import stat
import subprocess
import uuid

import pytest

SCRIPT_PATH = '/home/user/audit.py'
RESULTS_CSV_PATH = '/home/user/results.csv'
PLAN_TXT_PATH = '/home/user/plan.txt'
DB_PATH = '/home/user/compliance.db'


def run_audit(start, end, dept):
    for path in (RESULTS_CSV_PATH, PLAN_TXT_PATH):
        if os.path.lexists(path):
            os.remove(path)
    proc = subprocess.run(
        ['python3', SCRIPT_PATH, '--start', start, '--end', end, '--dept', dept],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert proc.returncode == 0, (
        f'audit.py failed with exit code {proc.returncode}. '
        f'stdout={proc.stdout!r}, stderr={proc.stderr!r}'
    )
    assert os.path.isfile(RESULTS_CSV_PATH), 'audit.py did not create results.csv'
    assert os.path.isfile(PLAN_TXT_PATH), 'audit.py did not create plan.txt'


@pytest.fixture(scope='session', autouse=True)
def run_original_case():
    run_audit('2023-10-01', '2023-10-31', 'Engineering')


def test_audit_script_and_required_construction():
    assert os.path.exists(SCRIPT_PATH), f'{SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a regular file.'
    assert not os.path.islink(SCRIPT_PATH), f'{SCRIPT_PATH} must not be a symlink.'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode)

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    imports_argparse = any(
        (isinstance(n, ast.Import) and any(a.name == 'argparse' for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module == 'argparse')
        for n in ast.walk(tree)
    )
    assert imports_argparse, 'audit.py must use the argparse module.'

    flags = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'add_argument':
            flags.update(
                arg.value for arg in node.args
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str)
            )
    assert {'--start', '--end', '--dept'} <= flags, 'argparse must define --start, --end, and --dept.'

    help_proc = subprocess.run(
        ['python3', SCRIPT_PATH, '--help'], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert help_proc.returncode == 0, 'audit.py --help must succeed.'
    help_text = (help_proc.stdout + help_proc.stderr).lower()
    assert all(flag in help_text for flag in ('--start', '--end', '--dept'))

    assert '/home/user/compliance.db' in source, 'audit.py must connect to the specified database.'
    assert re.search(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS', source, re.I), (
        'Indexes must be created with IF NOT EXISTS.'
    )

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            assignments[node.target.id] = node.value

    def expression_text(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            return expression_text(assignments[node.id], seen | {node.id})
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
            return expression_text(node.left, seen) + expression_text(node.right, seen)
        if isinstance(node, ast.JoinedStr):
            return ''.join(expression_text(v, seen) for v in node.values)
        return ''

    parameterized_select = False
    parameterized_explain = False
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'execute'):
            continue
        has_parameters = len(node.args) >= 2 or any(k.arg == 'parameters' for k in node.keywords)
        if not has_parameters or not node.args:
            continue
        sql_text = expression_text(node.args[0]).upper()
        if 'SELECT' in sql_text:
            parameterized_select = True
        if 'EXPLAIN QUERY PLAN' in sql_text:
            parameterized_explain = True

    assert parameterized_select, 'The SELECT must be executed with a separate parameter argument.'
    assert parameterized_explain, 'EXPLAIN QUERY PLAN must use the parameterized SELECT and its parameters.'
    assert re.search(r'\?|:[A-Za-z_][A-Za-z0-9_]*', source), 'No SQL parameter placeholders were found.'


def test_results_csv_content():
    """Verify the original requested invocation produces the correct data."""
    assert os.path.exists(RESULTS_CSV_PATH), f'{RESULTS_CSV_PATH} does not exist.'
    assert os.path.isfile(RESULTS_CSV_PATH), f'{RESULTS_CSV_PATH} is not a file.'

    expected_rows = [
        ['log_id', 'emp_name', 'asset_name', 'access_time'],
        ['2', 'Bob', 'Payroll DB', '2023-10-02 11:30:00'],
        ['4', 'Alice', 'Employee Records', '2023-10-15 14:20:00']
    ]
    with open(RESULTS_CSV_PATH, 'r', newline='') as f:
        actual_rows = list(csv.reader(f))
    assert actual_rows == expected_rows, f'CSV content does not match the expected output. Got: {actual_rows}'


def test_plan_txt_exists_and_valid():
    """Verify that plan.txt exists and looks like EXPLAIN QUERY PLAN output."""
    assert os.path.exists(PLAN_TXT_PATH), f'{PLAN_TXT_PATH} does not exist.'
    assert os.path.isfile(PLAN_TXT_PATH), f'{PLAN_TXT_PATH} is not a file.'
    with open(PLAN_TXT_PATH, 'r') as f:
        content = f.read().upper()
    assert 'SCAN' in content or 'SEARCH' in content, (
        f'{PLAN_TXT_PATH} does not appear to contain valid EXPLAIN QUERY PLAN output.'
    )


def test_indexes_created():
    """Verify that the script created indexes to optimize the query."""
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    indexes = conn.execute(
        "SELECT name, tbl_name FROM sqlite_master "
        "WHERE type='index' AND name NOT LIKE 'sqlite_%';"
    ).fetchall()
    conn.close()
    assert len(indexes) > 0, (
        'No custom indexes were found in the database. The script was supposed to create indexes to optimize the query.'
    )


def test_dynamic_data_dates_department_and_ordering():
    token = uuid.uuid4().hex
    target_dept = "Audit' OR 1=1 -- " + token
    other_dept = 'Other ' + token

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    next_dept = cur.execute('SELECT COALESCE(MAX(dept_id), 0) + 1 FROM departments').fetchone()[0]
    next_emp = cur.execute('SELECT COALESCE(MAX(emp_id), 0) + 1 FROM employees').fetchone()[0]
    next_asset = cur.execute('SELECT COALESCE(MAX(asset_id), 0) + 1 FROM restricted_assets').fetchone()[0]
    next_log = cur.execute('SELECT COALESCE(MAX(log_id), 0) + 1 FROM access_logs').fetchone()[0]

    target_dept_id, other_dept_id = next_dept, next_dept + 1
    target_emp_id, outsider_emp_id = next_emp, next_emp + 1
    own_asset_id, foreign_asset_id = next_asset, next_asset + 1

    cur.executemany('INSERT INTO departments VALUES (?, ?)', [
        (target_dept_id, target_dept), (other_dept_id, other_dept)
    ])
    cur.executemany('INSERT INTO employees VALUES (?, ?, ?)', [
        (target_emp_id, 'Target ' + token, target_dept_id),
        (outsider_emp_id, 'Outsider ' + token, other_dept_id)
    ])
    cur.executemany('INSERT INTO restricted_assets VALUES (?, ?, ?)', [
        (own_asset_id, 'Own ' + token, target_dept_id),
        (foreign_asset_id, 'Foreign ' + token, other_dept_id)
    ])

    logs = [
        (next_log, target_emp_id, foreign_asset_id, '2041-06-10 00:00:00'),
        (next_log + 2, target_emp_id, foreign_asset_id, '2041-06-11 12:00:00'),
        (next_log + 1, target_emp_id, foreign_asset_id, '2041-06-11 12:00:00'),
        (next_log + 3, target_emp_id, foreign_asset_id, '2041-06-12 23:59:59'),
        (next_log + 4, target_emp_id, own_asset_id, '2041-06-11 13:00:00'),
        (next_log + 5, outsider_emp_id, own_asset_id, '2041-06-11 14:00:00'),
        (next_log + 6, target_emp_id, foreign_asset_id, '2041-06-09 23:59:59'),
        (next_log + 7, target_emp_id, foreign_asset_id, '2041-06-13 00:00:00')
    ]
    cur.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
    conn.commit()

    expected = cur.execute(
        '''SELECT l.log_id, e.name, a.asset_name, l.access_time
           FROM access_logs AS l
           JOIN employees AS e ON e.emp_id = l.emp_id
           JOIN departments AS d ON d.dept_id = e.dept_id
           JOIN restricted_assets AS a ON a.asset_id = l.asset_id
           WHERE l.access_time >= ?
             AND l.access_time < datetime(?, '+1 day')
             AND d.dept_name = ?
             AND a.owning_dept_id <> e.dept_id
           ORDER BY l.access_time ASC, l.log_id ASC''',
        ('2041-06-10', '2041-06-12', target_dept)
    ).fetchall()
    conn.close()

    with open(PLAN_TXT_PATH, 'w', encoding='utf-8') as f:
        f.write('VERIFIER_SENTINEL')
    run_audit('2041-06-10', '2041-06-12', target_dept)

    with open(RESULTS_CSV_PATH, 'r', newline='') as f:
        actual = list(csv.reader(f))
    expected_csv = [['log_id', 'emp_name', 'asset_name', 'access_time']]
    expected_csv.extend([[str(row[0]), row[1], row[2], row[3]] for row in expected])
    assert actual == expected_csv, f'Dynamic audit result mismatch. Got: {actual}, expected: {expected_csv}'

    with open(PLAN_TXT_PATH, 'r', encoding='utf-8') as f:
        plan = f.read()
    assert 'VERIFIER_SENTINEL' not in plan, 'audit.py did not regenerate plan.txt.'
    assert 'SCAN' in plan.upper() or 'SEARCH' in plan.upper(), 'Regenerated plan.txt is not query-plan output.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
