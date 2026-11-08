#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import sqlite3 as _sqlite3

_TRACE = '/tmp/analyze_sqlite_trace.jsonl'
_original_connect = _sqlite3.connect

def _log(event):
    try:
        with open(_TRACE, 'a', encoding='utf-8') as f:
            f.write(json.dumps(event, default=repr) + '\n')
    except Exception:
        pass

def _detail(row):
    try:
        return str(row[-1])
    except Exception:
        return str(row)

class CursorProxy:
    def __init__(self, cursor, is_explain=False):
        object.__setattr__(self, '_cursor', cursor)
        object.__setattr__(self, '_is_explain', is_explain)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        if name in ('_cursor', '_is_explain'):
            object.__setattr__(self, name, value)
        else:
            setattr(self._cursor, name, value)

    def execute(self, sql, parameters=()):
        text = str(sql)
        _log({'event': 'sql', 'sql': text, 'parameters': repr(parameters)})
        object.__setattr__(self, '_is_explain', text.lstrip().upper().startswith('EXPLAIN QUERY PLAN'))
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        text = str(sql)
        _log({'event': 'sql', 'sql': text, 'parameters': '<executemany>'})
        object.__setattr__(self, '_is_explain', False)
        self._cursor.executemany(sql, seq_of_parameters)
        return self

    def executescript(self, sql_script):
        text = str(sql_script)
        _log({'event': 'sql', 'sql': text, 'parameters': '<script>'})
        object.__setattr__(self, '_is_explain', False)
        self._cursor.executescript(sql_script)
        return self

    def _record(self, rows):
        if self._is_explain:
            for row in rows:
                _log({'event': 'plan_detail', 'detail': _detail(row)})

    def fetchone(self):
        row = self._cursor.fetchone()
        if row is not None:
            self._record([row])
        return row

    def fetchmany(self, size=None):
        rows = self._cursor.fetchmany() if size is None else self._cursor.fetchmany(size)
        self._record(rows)
        return rows

    def fetchall(self):
        rows = self._cursor.fetchall()
        self._record(rows)
        return rows

    def __iter__(self):
        while True:
            row = self._cursor.fetchone()
            if row is None:
                break
            self._record([row])
            yield row

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        close = getattr(self._cursor, 'close', None)
        if close:
            close()
        return False

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        if name == '_connection':
            object.__setattr__(self, name, value)
        else:
            setattr(self._connection, name, value)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        text = str(sql)
        _log({'event': 'sql', 'sql': text, 'parameters': repr(parameters)})
        cursor = self._connection.execute(sql, parameters)
        return CursorProxy(cursor, text.lstrip().upper().startswith('EXPLAIN QUERY PLAN'))

    def executemany(self, sql, seq_of_parameters):
        text = str(sql)
        _log({'event': 'sql', 'sql': text, 'parameters': '<executemany>'})
        return CursorProxy(self._connection.executemany(sql, seq_of_parameters))

    def executescript(self, sql_script):
        text = str(sql_script)
        _log({'event': 'sql', 'sql': text, 'parameters': '<script>'})
        return CursorProxy(self._connection.executescript(sql_script))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, exc_type, exc, tb):
        return self._connection.__exit__(exc_type, exc, tb)

def connect(database, *args, **kwargs):
    _log({'event': 'connect', 'database': str(database), 'uri': bool(kwargs.get('uri', False))})
    return ConnectionProxy(_original_connect(database, *args, **kwargs))

_sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import re
import subprocess
import sys
import pytest

SCRIPT = '/home/user/analyze.py'
EMPLOYEES = '/home/user/employees.csv'
DEPARTMENTS = '/home/user/departments.csv'
OUTPUT = '/home/user/page2.json'
PLAN = '/home/user/query_plan.txt'
TRACE = '/tmp/analyze_sqlite_trace.jsonl'
HOOK_DIR = '/tmp/verifier_hook'


def read_trace():
    assert os.path.isfile(TRACE), 'The script did not produce a SQLite execution trace.'
    events = []
    with open(TRACE, encoding='utf-8') as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))
    return events


def run_analyze():
    for path in (OUTPUT, PLAN, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = HOOK_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')
    result = subprocess.run(
        [sys.executable, SCRIPT], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, 'analyze.py failed:\nSTDOUT:\n%s\nSTDERR:\n%s' % (result.stdout, result.stderr)
    assert os.path.isfile(OUTPUT), f'Expected output file {OUTPUT} is missing after running the script.'
    assert os.path.isfile(PLAN), f'Expected output file {PLAN} is missing after running the script.'
    return read_trace()


def assert_real_sqlite_work(events, plan_content):
    connects = [e for e in events if e.get('event') == 'connect']
    assert connects, 'analyze.py never opened a SQLite connection.'
    assert any(
        e.get('database') == ':memory:' or 'mode=memory' in e.get('database', '').lower() or
        e.get('database', '').lower().startswith('file::memory:')
        for e in connects
    ), 'analyze.py did not create an in-memory SQLite database.'

    sql_events = [e.get('sql', '') for e in events if e.get('event') == 'sql']
    combined = '\n'.join(sql_events)
    assert re.search(r'create\s+table[^;]*\bemployees\b', combined, re.I | re.S), 'No employees SQLite table was created.'
    assert re.search(r'create\s+table[^;]*\bdepartments\b', combined, re.I | re.S), 'No departments SQLite table was created.'
    assert re.search(r'insert\s+into\s+["`\[]?employees\b', combined, re.I), 'Employee CSV rows were not loaded into SQLite.'
    assert re.search(r'insert\s+into\s+["`\[]?departments\b', combined, re.I), 'Department CSV rows were not loaded into SQLite.'

    recursive = [sql for sql in sql_events if re.search(r'\bwith\s+recursive\b', sql, re.I)]
    assert recursive, 'No recursive CTE was executed.'
    explain = [sql for sql in sql_events if re.match(r'\s*explain\s+query\s+plan\b', sql, re.I)]
    assert explain, 'SQLite EXPLAIN QUERY PLAN was not executed.'
    final_explain = next((sql for sql in explain if re.search(r'\bwith\s+recursive\b', sql, re.I)), None)
    assert final_explain is not None, 'EXPLAIN QUERY PLAN was not run on the recursive final query.'
    for pattern, description in [
        (r'\bdepartments\b', 'department join'),
        (r'\bsalary\b[^;]*>', 'salary filter'),
        (r'\border\s+by\b', 'required ordering'),
        (r'\blimit\b', 'pagination'),
    ]:
        assert re.search(pattern, final_explain, re.I | re.S), f'The explained final query is missing the {description}.'

    details = [str(e.get('detail')) for e in events if e.get('event') == 'plan_detail']
    assert details, 'The result rows from EXPLAIN QUERY PLAN were never retrieved.'
    assert all(detail in plan_content for detail in details), 'query_plan.txt does not contain the plan details returned by SQLite.'


def validate_plan_text(content):
    assert len(content) > 0, f'File {PLAN} is empty.'
    assert any(keyword in content.upper() for keyword in ['SCAN', 'SEARCH', 'COROUTINE', 'CTE', 'B-TREE', 'COMPOUND']), \
        f'File {PLAN} does not appear to contain a valid EXPLAIN QUERY PLAN output.'


def expected_from_csv():
    with open(EMPLOYEES, newline='', encoding='utf-8') as f:
        employees = list(csv.DictReader(f))
    with open(DEPARTMENTS, newline='', encoding='utf-8') as f:
        departments = {int(r['dept_id']): r['dept_name'] for r in csv.DictReader(f)}

    by_manager = {}
    for row in employees:
        manager = row['manager_id'].strip()
        if manager:
            by_manager.setdefault(int(manager), []).append(row)

    result = []
    frontier = [(row, 1) for row in by_manager.get(1, [])]
    while frontier:
        row, depth = frontier.pop(0)
        salary = int(row['salary'])
        if salary > 50000:
            result.append({
                'id': int(row['id']),
                'name': row['name'],
                'dept_name': departments[int(row['department'])],
                'salary': salary,
                'depth': depth,
            })
        frontier.extend((child, depth + 1) for child in by_manager.get(int(row['id']), []))
    result.sort(key=lambda r: (r['depth'], -r['salary'], r['name']))
    return result[5:10]


def test_00_analyze_py_exists_and_runs():
    assert os.path.isfile(SCRIPT), f'Expected script {SCRIPT} is missing.'
    assert not os.path.islink(SCRIPT), f'Expected {SCRIPT} to be a regular script, not a symlink.'
    with open(SCRIPT, encoding='utf-8') as f:
        source = f.read()
    ast.parse(source, filename=SCRIPT)
    events = run_analyze()
    with open(PLAN, encoding='utf-8') as f:
        plan_content = f.read().strip()
    assert_real_sqlite_work(events, plan_content)


def test_page2_json_valid():
    assert os.path.isfile(OUTPUT), f'Expected output file {OUTPUT} is missing.'
    with open(OUTPUT, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {OUTPUT} is not valid JSON.')

    assert isinstance(data, list), f'Expected JSON in {OUTPUT} to be a list of objects.'
    expected_data = [
        {'id': 4, 'name': 'David', 'dept_name': 'Engineering', 'salary': 80000, 'depth': 2},
        {'id': 9, 'name': 'Ivan', 'dept_name': 'Executive', 'salary': 75000, 'depth': 2},
        {'id': 16, 'name': 'Victor', 'dept_name': 'Engineering', 'salary': 71000, 'depth': 2},
        {'id': 6, 'name': 'Frank', 'dept_name': 'Sales', 'salary': 60000, 'depth': 2},
        {'id': 8, 'name': 'Heidi', 'dept_name': 'Marketing', 'salary': 55000, 'depth': 2},
    ]
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} records in {OUTPUT}, but got {len(data)}.'
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f'Record at index {i} is not a JSON object.'
        assert set(actual) == {'id', 'name', 'dept_name', 'salary', 'depth'}, f'Record at index {i} has incorrect keys.'
        for key in ['id', 'name', 'dept_name', 'salary', 'depth']:
            assert key in actual, f"Record at index {i} is missing key '{key}'."
            assert actual[key] == expected[key], f"Mismatch at index {i} for key '{key}': expected {expected[key]}, got {actual[key]}."
        assert type(actual['id']) is int and type(actual['salary']) is int and type(actual['depth']) is int


def test_query_plan_txt_valid():
    assert os.path.isfile(PLAN), f'Expected output file {PLAN} is missing.'
    with open(PLAN, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    validate_plan_text(content)


def test_script_handles_derived_alternate_input():
    paths = [EMPLOYEES, DEPARTMENTS, OUTPUT, PLAN]
    saved = {path: (open(path, 'rb').read() if os.path.exists(path) else None) for path in paths}
    try:
        employee_rows = [
            ['id', 'name', 'department', 'salary', 'manager_id'],
            [1, 'Root', 10, 200000, ''],
            [2, 'Alpha', 10, 70000, 1], [3, 'Beta', 20, 130000, 1],
            [4, 'Gamma', 10, 51000, 1], [5, 'Delta', 30, 49000, 1],
            [6, 'Epsilon', 30, 90000, 1], [7, 'Zeta', 20, 80000, 1],
            [8, 'Eta', 30, 125000, 2], [9, 'Theta', 10, 60000, 2],
            [10, 'Iota', 20, 110000, 3], [11, 'Kappa', 30, 52000, 6],
            [12, 'Lambda', 20, 100000, 7], [13, 'Mu', 10, 140000, 8],
            [14, 'Nu', 20, 53000, 10], [15, 'Xi', 30, 50001, 11],
        ]
        department_rows = [
            ['dept_id', 'dept_name', 'parent_dept_id'],
            [10, 'Orchid', ''], [20, 'Cobalt', 10], [30, 'Amber', 10],
        ]
        with open(EMPLOYEES, 'w', newline='', encoding='utf-8') as f:
            csv.writer(f).writerows(employee_rows)
        with open(DEPARTMENTS, 'w', newline='', encoding='utf-8') as f:
            csv.writer(f).writerows(department_rows)

        expected = expected_from_csv()
        events = run_analyze()
        with open(OUTPUT, encoding='utf-8') as f:
            actual = json.load(f)
        with open(PLAN, encoding='utf-8') as f:
            plan_content = f.read().strip()
        assert actual == expected, 'analyze.py did not derive the paginated hierarchy from alternate CSV input.'
        validate_plan_text(plan_content)
        assert_real_sqlite_work(events, plan_content)
    finally:
        for path, content in saved.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
