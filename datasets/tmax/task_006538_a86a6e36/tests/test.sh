#!/bin/bash
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_analyze_instrumented.py
import json
import runpy
import sqlite3
import sys

trace_path = sys.argv[1]
sql_statements = []
jsonschema_called = False
real_connect = sqlite3.connect

class CursorProxy:
    def __init__(self, inner):
        object.__setattr__(self, '_inner', inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name == '_inner':
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)

    def execute(self, sql, *args, **kwargs):
        sql_statements.append(str(sql))
        self._inner.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        sql_statements.append(str(sql))
        self._inner.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        sql_statements.append(str(sql))
        self._inner.executescript(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._inner)

class ConnectionProxy:
    def __init__(self, inner):
        object.__setattr__(self, '_inner', inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name == '_inner':
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._inner.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        sql_statements.append(str(sql))
        return CursorProxy(self._inner.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        sql_statements.append(str(sql))
        return CursorProxy(self._inner.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        sql_statements.append(str(sql))
        return CursorProxy(self._inner.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

def traced_connect(*args, **kwargs):
    return ConnectionProxy(real_connect(*args, **kwargs))

def profiler(frame, event, arg):
    global jsonschema_called
    if event == 'call':
        filename = frame.f_code.co_filename.replace('\\', '/').lower()
        function = frame.f_code.co_name
        if '/jsonschema/' in filename and function in {'validate', 'iter_errors', 'is_valid'}:
            jsonschema_called = True
    return profiler

sqlite3.connect = traced_connect
sys.setprofile(profiler)
try:
    runpy.run_path('/home/user/analyze_backups.py', run_name='__main__')
finally:
    sys.setprofile(None)
    with open(trace_path, 'w', encoding='utf-8') as f:
        json.dump({'sql': sql_statements, 'jsonschema_called': jsonschema_called}, f)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

import jsonschema

DB_PATH = '/home/user/backups.db'
RESULTS_PATH = '/home/user/analysis_results.json'
SCRIPT_PATH = '/home/user/analyze_backups.py'
RUNNER_PATH = '/tmp/run_analyze_instrumented.py'

SCHEMA = {
    'type': 'array',
    'items': {
        'type': 'object',
        'properties': {
            'root_backup_id': {'type': 'integer'},
            'db_name': {'type': 'string'},
            'total_chain_size': {'type': 'integer'},
            'is_anomalous': {'type': 'boolean'},
        },
        'required': ['root_backup_id', 'db_name', 'total_chain_size', 'is_anomalous'],
    },
}

INITIAL_ROWS = [
    (1, 'auth_db', '2023-10-01 00:00:00', 100, None, 'SUCCESS'),
    (2, 'auth_db', '2023-10-02 00:00:00', 10, 1, 'SUCCESS'),
    (3, 'auth_db', '2023-10-03 00:00:00', 15, 2, 'SUCCESS'),
    (4, 'auth_db', '2023-10-08 00:00:00', 110, None, 'SUCCESS'),
    (5, 'auth_db', '2023-10-09 00:00:00', 20, 4, 'SUCCESS'),
    (6, 'auth_db', '2023-10-15 00:00:00', 250, None, 'SUCCESS'),
    (7, 'auth_db', '2023-10-16 00:00:00', 50, 6, 'SUCCESS'),
    (8, 'users_db', '2023-10-01 00:00:00', 500, None, 'SUCCESS'),
    (9, 'users_db', '2023-10-08 00:00:00', 550, None, 'SUCCESS'),
    (10, 'users_db', '2023-10-15 00:00:00', 600, None, 'SUCCESS'),
]

INITIAL_EXPECTED = {
    1: {'db_name': 'auth_db', 'total_chain_size': 125, 'is_anomalous': False},
    4: {'db_name': 'auth_db', 'total_chain_size': 130, 'is_anomalous': False},
    6: {'db_name': 'auth_db', 'total_chain_size': 300, 'is_anomalous': True},
    8: {'db_name': 'users_db', 'total_chain_size': 500, 'is_anomalous': False},
    9: {'db_name': 'users_db', 'total_chain_size': 550, 'is_anomalous': False},
    10: {'db_name': 'users_db', 'total_chain_size': 600, 'is_anomalous': False},
}

def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.unlink(path)

def create_database(rows):
    remove_path(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE backup_jobs (
        id INTEGER PRIMARY KEY,
        db_name TEXT,
        start_time DATETIME,
        size_bytes INTEGER,
        parent_backup_id INTEGER,
        status TEXT
    )''')
    conn.executemany('INSERT INTO backup_jobs VALUES (?, ?, ?, ?, ?, ?)', rows)
    conn.commit()
    conn.close()
    os.chmod(DB_PATH, 0o666)

def run_script():
    remove_path(RESULTS_PATH)
    fd, trace_path = tempfile.mkstemp(prefix='analysis_trace_', suffix='.json')
    os.close(fd)
    try:
        proc = subprocess.run(
            [sys.executable, RUNNER_PATH, trace_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert proc.returncode == 0, (
            'analyze_backups.py failed when executed autonomously.\n'
            f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
        )
        with open(trace_path, encoding='utf-8') as f:
            trace = json.load(f)
    finally:
        if os.path.exists(trace_path):
            os.unlink(trace_path)

    statements = trace.get('sql', [])
    assert any(re.search(r'\bWITH\s+RECURSIVE\b', sql, re.I) for sql in statements), \
        'The executed analysis did not use a recursive CTE.'
    assert any(re.search(r'\bOVER\s*\(', sql, re.I) for sql in statements), \
        'The executed analysis did not use a SQL window function.'
    assert trace.get('jsonschema_called') is True, \
        'The script did not perform validation through the jsonschema library.'

def assert_indexes_created():
    assert os.path.exists(DB_PATH), f'Database file missing at {DB_PATH}'
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = conn.execute("PRAGMA index_list('backup_jobs')").fetchall()
        assert len(indexes) > 0, "No indexes were created on the 'backup_jobs' table."
        indexed_columns = []
        for index in indexes:
            escaped = index[1].replace("'", "''")
            columns = [row[2] for row in conn.execute(f"PRAGMA index_info('{escaped}')")]
            indexed_columns.append(columns)
    finally:
        conn.close()

    assert any('parent_backup_id' in cols for cols in indexed_columns), \
        "Missing index on 'parent_backup_id' for hierarchical queries."
    has_window_idx = (
        any('db_name' in cols and 'start_time' in cols for cols in indexed_columns)
        or (any('db_name' in cols for cols in indexed_columns)
            and any('start_time' in cols for cols in indexed_columns))
    )
    assert has_window_idx, "Missing index on 'db_name' and/or 'start_time' for window functions."

def load_and_validate_results():
    assert os.path.exists(RESULTS_PATH), f'Results file missing at {RESULTS_PATH}'
    assert os.path.isfile(RESULTS_PATH), f'Expected a file at {RESULTS_PATH}, but found a directory'
    with open(RESULTS_PATH, encoding='utf-8') as f:
        data = json.load(f)
    jsonschema.validate(instance=data, schema=SCHEMA)
    return data

def assert_expected(data, expected):
    assert isinstance(data, list), 'JSON root must be an array.'
    assert len(data) == len(expected), f'Expected {len(expected)} backup chains, found {len(data)}.'
    results_by_id = {item['root_backup_id']: item for item in data}
    assert len(results_by_id) == len(data), 'Duplicate root_backup_id values were returned.'
    for root_id, wanted in expected.items():
        assert root_id in results_by_id, f'Missing root_backup_id {root_id} in results.'
        actual = results_by_id[root_id]
        for key in ['db_name', 'total_chain_size', 'is_anomalous']:
            assert key in actual, f"Missing key '{key}' in result for root_backup_id {root_id}."
        assert actual['db_name'] == wanted['db_name'], f'db_name mismatch for root {root_id}'
        assert actual['total_chain_size'] == wanted['total_chain_size'], \
            f'total_chain_size mismatch for root {root_id}'
        assert actual['is_anomalous'] is wanted['is_anomalous'], \
            f'is_anomalous mismatch for root {root_id}'

def make_random_fixture():
    rng = random.SystemRandom()
    token = secrets.token_hex(4)
    ids = iter(rng.sample(range(1000, 900000), 48))
    rows = []

    for db_number in range(3):
        db_name = f'db_{token}_{db_number}'
        base_date = datetime.datetime(2025, 1, 1) + datetime.timedelta(days=db_number)
        target_totals = [
            1000 + rng.randrange(0, 80),
            1200 + rng.randrange(0, 80),
            5000 + rng.randrange(0, 150),
            1400 + rng.randrange(0, 80),
        ]
        for sequence, target in enumerate(target_totals):
            root_id, child_id, grandchild_id, branch_id = next(ids), next(ids), next(ids), next(ids)
            child_size = rng.randrange(40, 90)
            grandchild_size = rng.randrange(20, 60)
            branch_size = rng.randrange(30, 75)
            root_size = target - child_size - grandchild_size - branch_size
            root_time = base_date + datetime.timedelta(days=sequence * 10)
            fmt = lambda value: value.strftime('%Y-%m-%d %H:%M:%S')
            rows.extend([
                (root_id, db_name, fmt(root_time), root_size, None, 'SUCCESS'),
                (child_id, db_name, fmt(root_time + datetime.timedelta(days=1)), child_size, root_id, 'SUCCESS'),
                (grandchild_id, db_name, fmt(root_time + datetime.timedelta(days=2)), grandchild_size, child_id, 'SUCCESS'),
                (branch_id, db_name, fmt(root_time + datetime.timedelta(days=3)), branch_size, root_id, 'SUCCESS'),
            ])
    rng.shuffle(rows)
    return rows

def derive_expected(rows):
    by_id = {row[0]: row for row in rows}
    children = {}
    roots = []
    for row in rows:
        if row[4] is None:
            roots.append(row)
        else:
            children.setdefault(row[4], []).append(row[0])

    def total(node_id):
        return by_id[node_id][3] + sum(total(child) for child in children.get(node_id, []))

    grouped = {}
    for root in roots:
        grouped.setdefault(root[1], []).append(root)

    expected = {}
    for db_name, db_roots in grouped.items():
        db_roots.sort(key=lambda row: row[2])
        prior_totals = []
        for root in db_roots:
            chain_total = total(root[0])
            anomalous = False
            if len(prior_totals) >= 2:
                previous_average = sum(prior_totals[-2:]) / 2.0
                anomalous = chain_total > 1.5 * previous_average
            expected[root[0]] = {
                'db_name': db_name,
                'total_chain_size': chain_total,
                'is_anomalous': anomalous,
            }
            prior_totals.append(chain_total)
    return expected

def main():
    assert os.path.isfile(SCRIPT_PATH), f'Missing required script at {SCRIPT_PATH}'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f'{SCRIPT_PATH} is not a regular file'

    # Rebuild and test the original fixture, preserving all original assertions.
    create_database(INITIAL_ROWS)
    run_script()
    assert_indexes_created()
    assert_expected(load_and_validate_results(), INITIAL_EXPECTED)

    # Exercise the artifact against an unpredictable hierarchy and window sequence.
    random_rows = make_random_fixture()
    random_expected = derive_expected(random_rows)
    create_database(random_rows)
    run_script()
    assert_indexes_created()
    assert_expected(load_and_validate_results(), random_expected)

if __name__ == '__main__':
    main()
TEST_EOF

if timeout 90s python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
