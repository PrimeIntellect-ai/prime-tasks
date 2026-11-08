#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("SQLITE_QUERY_TRACE")

def _record(sql):
    if _trace_path:
        with open(_trace_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"sql": str(sql)}) + "\n")

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, *args, **kwargs):
        _record(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        _record(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        _record(sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __next__(self):
        return next(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        _record(sql)
        return CursorProxy(self._connection.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        _record(sql)
        return CursorProxy(self._connection.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        _record(sql)
        return CursorProxy(self._connection.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        if name == "_connection":
            object.__setattr__(self, name, value)
        else:
            setattr(self._connection, name, value)

def traced_connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = traced_connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import uuid
import pytest

DB_PATH = '/home/user/audit.db'
JSON_PATH = '/home/user/violations.json'
PIPELINE_PATH = '/home/user/run_pipeline.sh'
EXTRACTOR_PATH = '/home/user/extract_violations.py'
TRACE_PATH = '/tmp/sqlite_query_trace.jsonl'
EXPECTED_KEYS = {'log_id', 'employee_name', 'system_name', 'violation_type'}


def compute_expected(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    query = """
        SELECT
            a.log_id,
            e.name as employee_name,
            s.sys_name as system_name,
            e.clearance_level,
            s.required_clearance,
            e.termination_date,
            a.access_timestamp
        FROM access_logs a
        JOIN employees e ON a.emp_id = e.emp_id
        JOIN systems s ON a.sys_id = s.sys_id
    """
    c.execute(query)
    rows = c.fetchall()
    conn.close()

    expected_violations = []
    for row in rows:
        access_date = row['access_timestamp'].split(' ')[0]
        is_terminated = row['termination_date'] is not None and access_date > row['termination_date']
        is_clearance_violation = row['clearance_level'] < row['required_clearance']

        if is_terminated:
            violation_type = 'TERMINATED'
        elif is_clearance_violation:
            violation_type = 'CLEARANCE'
        else:
            continue

        expected_violations.append({
            'log_id': row['log_id'],
            'employee_name': row['employee_name'],
            'system_name': row['system_name'],
            'violation_type': violation_type,
        })

    expected_violations.sort(key=lambda x: x['log_id'])
    return expected_violations


def load_and_check_json(path):
    assert os.path.exists(path), f'Output file {path} does not exist.'
    with open(path, 'r', encoding='utf-8') as f:
        try:
            value = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{path} does not contain valid JSON.')

    assert isinstance(value, list), f'JSON root in {path} must be a list.'
    for i, item in enumerate(value):
        assert isinstance(item, dict), f'Item {i} must be an object.'
        assert set(item.keys()) == EXPECTED_KEYS, f'Item {i} must contain exactly {sorted(EXPECTED_KEYS)}.'
        assert type(item['log_id']) is int, f'Item {i} log_id must be an integer.'
        assert type(item['employee_name']) is str, f'Item {i} employee_name must be a string.'
        assert type(item['system_name']) is str, f'Item {i} system_name must be a string.'
        assert type(item['violation_type']) is str, f'Item {i} violation_type must be a string.'
        assert item['violation_type'] in {'TERMINATED', 'CLEARANCE'}, f'Item {i} has an invalid violation_type.'
    return value


def test_01_required_scripts_exist_and_pipeline_is_executable():
    assert os.path.exists(EXTRACTOR_PATH), f'Script {EXTRACTOR_PATH} does not exist.'
    assert os.path.isfile(EXTRACTOR_PATH), f'{EXTRACTOR_PATH} is not a file.'

    assert os.path.exists(PIPELINE_PATH), f'Script {PIPELINE_PATH} does not exist.'
    assert os.path.isfile(PIPELINE_PATH), f'{PIPELINE_PATH} is not a file.'
    assert os.access(PIPELINE_PATH, os.X_OK), f'{PIPELINE_PATH} is not executable.'


def test_02_execute_pipeline_on_derived_data_and_check_single_query():
    assert os.path.exists(DB_PATH), f'Database {DB_PATH} is missing.'

    token = uuid.uuid4().hex
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    next_emp = c.execute('SELECT COALESCE(MAX(emp_id), 0) + 1 FROM employees').fetchone()[0]
    next_sys = c.execute('SELECT COALESCE(MAX(sys_id), 0) + 1 FROM systems').fetchone()[0]
    next_log = c.execute('SELECT COALESCE(MAX(log_id), 0) + 1 FROM access_logs').fetchone()[0]

    employees = [
        (next_emp, 'DynamicLive_' + token, 1, None),
        (next_emp + 1, 'DynamicTerminated_' + token, 5, '2031-01-10'),
        (next_emp + 2, 'DynamicBoth_' + token, 1, '2031-01-10'),
    ]
    systems = [(next_sys, 'DynamicSystem_' + token, 4)]
    logs = [
        (next_log, next_emp, next_sys, '2031-01-10 08:00:00'),
        (next_log + 1, next_emp + 1, next_sys, '2031-01-11 08:00:00'),
        (next_log + 2, next_emp + 1, next_sys, '2031-01-10 23:59:59'),
        (next_log + 3, next_emp + 2, next_sys, '2031-01-11 08:00:00'),
    ]
    c.executemany('INSERT INTO employees VALUES (?, ?, ?, ?)', employees)
    c.executemany('INSERT INTO systems VALUES (?, ?, ?)', systems)
    c.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
    conn.commit()
    conn.close()

    expected_before_run = compute_expected(DB_PATH)
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    env['SQLITE_QUERY_TRACE'] = TRACE_PATH
    env['PYTHONPATH'] = '/tmp/verifier_hook' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        [PIPELINE_PATH],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f'Pipeline failed with stderr:\n{result.stderr}'
    assert 'Pipeline successful' in result.stdout, 'Pipeline did not print "Pipeline successful".'

    actual = load_and_check_json(JSON_PATH)
    assert actual == expected_before_run, 'Pipeline output did not match the violations derived from the exercised database.'
    assert [x['log_id'] for x in actual] == sorted(x['log_id'] for x in actual), 'Output is not sorted by log_id.'

    assert os.path.exists(TRACE_PATH), 'The extractor did not execute a traceable SQLite query.'
    with open(TRACE_PATH, 'r', encoding='utf-8') as f:
        statements = [json.loads(line)['sql'] for line in f if line.strip()]
    assert len(statements) == 1, f'Expected exactly one SQLite query, but observed {len(statements)}.'
    normalized = ' '.join(statements[0].lower().split())
    assert normalized.startswith('select') or normalized.startswith('with'), 'The single SQLite statement must be a query.'
    for table in ('access_logs', 'employees', 'systems'):
        assert table in normalized, f'The single query does not reference {table}.'


def test_03_violations_json_correctness():
    actual_violations = load_and_check_json(JSON_PATH)
    expected_violations = compute_expected(DB_PATH)

    assert len(actual_violations) == len(expected_violations), f'Expected {len(expected_violations)} violations, but found {len(actual_violations)}.'

    for i, (actual, expected) in enumerate(zip(actual_violations, expected_violations)):
        assert actual.get('log_id') == expected['log_id'], f"Mismatch at index {i}: expected log_id {expected['log_id']}, got {actual.get('log_id')}"
        assert actual.get('employee_name') == expected['employee_name'], f"Mismatch at index {i}: expected employee_name {expected['employee_name']}, got {actual.get('employee_name')}"
        assert actual.get('system_name') == expected['system_name'], f"Mismatch at index {i}: expected system_name {expected['system_name']}, got {actual.get('system_name')}"
        assert actual.get('violation_type') == expected['violation_type'], f"Mismatch at index {i}: expected violation_type {expected['violation_type']}, got {actual.get('violation_type')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
