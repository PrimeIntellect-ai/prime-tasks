#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import sqlite3
import subprocess
import sys
import uuid

import pytest

DB_PATH = '/home/user/expenses.db'
SCRIPT_PATH = '/home/user/audit.py'
REPORT_PATH = '/home/user/audit_report.json'
EXPECTED_KEYS = {
    'employee_name', 'department', 'category', 'amount',
    'category_average', 'date'
}


def get_expected_data(db_path, dept_name):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    query = """
    WITH CatAvg AS (
        SELECT cat_id, AVG(amount) as raw_avg
        FROM expenses
        GROUP BY cat_id
    )
    SELECT
        e.name as employee_name,
        d.name as department,
        c.name as category,
        ex.amount as amount,
        ROUND(ca.raw_avg, 2) as category_average,
        ex.date
    FROM expenses ex
    JOIN employees e ON ex.emp_id = e.id
    JOIN departments d ON e.department_id = d.id
    JOIN categories c ON ex.cat_id = c.id
    JOIN CatAvg ca ON ex.cat_id = ca.cat_id
    WHERE d.name = ? AND ex.amount > ca.raw_avg
    ORDER BY ex.date ASC, ex.amount DESC
    """
    c.execute(query, (dept_name,))
    columns = ['employee_name', 'department', 'category', 'amount', 'category_average', 'date']
    results = [dict(zip(columns, row)) for row in c.fetchall()]
    conn.close()
    return results


def load_report(context=''):
    assert os.path.exists(REPORT_PATH), f'Report file is missing {context}'
    try:
        with open(REPORT_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'{REPORT_PATH} is not valid JSON {context}: {exc}')
    assert isinstance(data, list), f'Expected JSON root to be a list, got {type(data).__name__}.'
    return data


def assert_report(data, expected, context):
    assert len(data) == len(expected), f'Expected {len(expected)} records {context}, got {len(data)}.'
    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f'Record {i} {context} is not an object.'
        assert set(actual) == EXPECTED_KEYS, f'Record {i} {context} does not have the exact required keys.'
        assert isinstance(actual['employee_name'], str)
        assert isinstance(actual['department'], str)
        assert isinstance(actual['category'], str)
        assert isinstance(actual['amount'], float), f"Record {i} {context}: amount must be a float."
        assert isinstance(actual['category_average'], float), f"Record {i} {context}: category_average must be a float."
        assert isinstance(actual['date'], str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', actual['date'])
        for key in EXPECTED_KEYS:
            if key == 'category_average':
                assert abs(actual[key] - wanted[key]) < 0.001, (
                    f'Mismatch in {key} for record {i} {context}: expected {wanted[key]}, got {actual[key]}'
                )
            else:
                assert actual[key] == wanted[key], (
                    f'Mismatch in {key} for record {i} {context}: expected {wanted[key]}, got {actual[key]}'
                )


def run_script(department, env=None):
    return subprocess.run(
        ['python3', SCRIPT_PATH, department], capture_output=True, text=True, env=env
    )


def test_audit_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f'The script {SCRIPT_PATH} is missing or is not a regular file.'


def test_audit_report_json_exists():
    assert os.path.exists(REPORT_PATH), f'The report file {REPORT_PATH} is missing. Did you run the script?'


def test_audit_report_json_contents():
    data = load_report("for the required initial 'Sales' run")
    assert_report(data, get_expected_data(DB_PATH, 'Sales'), "for 'Sales'")


def test_exact_argument_handling():
    sentinel = b'verifier-sentinel-report'
    with open(REPORT_PATH, 'wb') as f:
        f.write(sentinel)

    no_arg = subprocess.run(['python3', SCRIPT_PATH], capture_output=True, text=True)
    assert no_arg.returncode != 0, 'The script must reject invocation with no department argument.'
    assert open(REPORT_PATH, 'rb').read() == sentinel, 'Invalid no-argument invocation overwrote the report.'

    too_many = subprocess.run(['python3', SCRIPT_PATH, 'Sales', 'extra'], capture_output=True, text=True)
    assert too_many.returncode != 0, 'The script must reject invocation with more than one argument.'
    assert open(REPORT_PATH, 'rb').read() == sentinel, 'Invalid multi-argument invocation overwrote the report.'


def test_audit_script_dynamic_parameterization():
    result = run_script('Engineering')
    assert result.returncode == 0, f"Script failed when run with 'Engineering'. Error: {result.stderr}"
    data = load_report("after running for 'Engineering'")
    assert_report(data, get_expected_data(DB_PATH, 'Engineering'), "for 'Engineering'")


def install_sqlite_trace_hook(hook_dir, log_path):
    os.makedirs(hook_dir, exist_ok=True)
    hook = r'''
import json
import os
import sqlite3 as _sqlite3

_LOG = os.environ.get('AUDIT_SQL_LOG')
_MISSING = object()
_real_connect = _sqlite3.connect


def _record(event):
    if _LOG:
        with open(_LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps(event, default=repr) + '\n')


def _params_repr(parameters):
    return None if parameters is _MISSING else repr(parameters)


class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=_MISSING):
        _record({'kind': 'execute', 'sql': str(sql), 'params': _params_repr(parameters)})
        if parameters is _MISSING:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, parameters):
        _record({'kind': 'executemany', 'sql': str(sql), 'params': repr(parameters)})
        self._cursor.executemany(sql, parameters)
        return self

    def executescript(self, sql):
        _record({'kind': 'executescript', 'sql': str(sql), 'params': None})
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_MISSING):
        cursor = self.cursor()
        return cursor.execute(sql, parameters) if parameters is not _MISSING else cursor.execute(sql)

    def executemany(self, sql, parameters):
        return self.cursor().executemany(sql, parameters)

    def executescript(self, sql):
        return self.cursor().executescript(sql)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def connect(*args, **kwargs):
    path = args[0] if args else kwargs.get('database')
    _record({'kind': 'connect', 'path': str(path)})
    return ConnectionProxy(_real_connect(*args, **kwargs))


_sqlite3.connect = connect
'''
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(hook)
    if os.path.exists(log_path):
        os.remove(log_path)


def add_randomized_fixture():
    token = uuid.uuid4().hex
    target = f"Audit_{token}' OR 1=1 --"
    outsider = f'Outside_{token}'
    base = random.SystemRandom().randint(300, 3000)

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    next_dept = c.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM departments').fetchone()[0]
    next_emp = c.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM employees').fetchone()[0]
    next_cat = c.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM categories').fetchone()[0]
    next_exp = c.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM expenses').fetchone()[0]

    c.executemany('INSERT INTO departments(id, name) VALUES (?, ?)', [
        (next_dept, target), (next_dept + 1, outsider)
    ])
    c.executemany('INSERT INTO employees(id, name, role, department_id) VALUES (?, ?, ?, ?)', [
        (next_emp, f'TargetA_{token}', 'Auditor', next_dept),
        (next_emp + 1, f'TargetB_{token}', 'Auditor', next_dept),
        (next_emp + 2, f'Outsider_{token}', 'Auditor', next_dept + 1),
    ])
    c.executemany('INSERT INTO categories(id, name) VALUES (?, ?)', [
        (next_cat, f'RandomCatA_{token}'),
        (next_cat + 1, f'RandomCatB_{token}'),
    ])
    rows = [
        (next_exp, next_emp, next_cat, float(base + 100.11), '2041-02-03'),
        (next_exp + 1, next_emp + 1, next_cat, float(base - 50.22), '2041-02-01'),
        (next_exp + 2, next_emp + 2, next_cat, float(base + 10.37), '2041-02-02'),
        (next_exp + 3, next_emp, next_cat + 1, float(base + 80.44), '2041-01-15'),
        (next_exp + 4, next_emp + 1, next_cat + 1, float(base + 90.55), '2041-01-15'),
        (next_exp + 5, next_emp + 2, next_cat + 1, float(base - 100.00), '2041-01-14'),
    ]
    c.executemany('INSERT INTO expenses(id, emp_id, cat_id, amount, date) VALUES (?, ?, ?, ?, ?)', rows)
    conn.commit()
    conn.close()
    return target


def test_randomized_database_and_required_sql_implementation(tmp_path):
    target = add_randomized_fixture()
    expected = get_expected_data(DB_PATH, target)
    assert len(expected) == 3, 'Verifier fixture did not produce the intended suspicious rows.'

    hook_dir = str(tmp_path / 'hook')
    log_path = str(tmp_path / 'sqlite-log.jsonl')
    install_sqlite_trace_hook(hook_dir, log_path)
    env = os.environ.copy()
    env['AUDIT_SQL_LOG'] = log_path
    env['PYTHONPATH'] = hook_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')

    result = run_script(target, env=env)
    assert result.returncode == 0, f'Script failed on randomized department name: {result.stderr}'
    assert_report(load_report('for randomized department'), expected, 'for randomized department')

    assert os.path.exists(log_path), 'No sqlite3 activity was observed; the built-in sqlite3 module must be used.'
    with open(log_path, 'r', encoding='utf-8') as f:
        events = [json.loads(line) for line in f if line.strip()]

    assert any(e.get('kind') == 'connect' and e.get('path') == DB_PATH for e in events), (
        f'The script must connect to {DB_PATH} using sqlite3.'
    )

    qualifying = []
    for event in events:
        if event.get('kind') != 'execute':
            continue
        sql = event.get('sql', '')
        upper = sql.upper()
        params = event.get('params')
        has_subquery_or_cte = re.search(r'\bWITH\b', upper) or len(re.findall(r'\bSELECT\b', upper)) >= 2
        required_tables = all(re.search(r'\b' + name + r'\b', upper) for name in (
            'EXPENSES', 'EMPLOYEES', 'DEPARTMENTS', 'CATEGORIES'
        ))
        parameter_marker = '?' in sql or re.search(r'[:@$][A-Za-z_]\w*', sql)
        if (
            re.search(r'\bSELECT\b', upper)
            and re.search(r'\bAVG\s*\(', upper)
            and has_subquery_or_cte
            and required_tables
            and len(re.findall(r'\bJOIN\b', upper)) >= 3
            and parameter_marker
            and params is not None
            and target in params
        ):
            qualifying.append(event)

    assert qualifying, (
        'The observed SQL must use the supplied department as a bound parameter in a query that '
        'calculates AVG in SQLite and features the required joins and a subquery or CTE.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
