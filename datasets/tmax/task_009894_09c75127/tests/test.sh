#!/bin/bash
set -e
mkdir -p /logs/verifier

DB_BACKUP=/tmp/events.db.verifier_backup
OUTPUT_BACKUP=/tmp/output.json.verifier_backup
cp /home/user/events.db "$DB_BACKUP"
if [ -f /home/user/output.json ]; then
    cp /home/user/output.json "$OUTPUT_BACKUP"
    HAD_OUTPUT=1
else
    HAD_OUTPUT=0
fi

restore_state() {
    rm -f /home/user/events.db /home/user/events.db-wal /home/user/events.db-shm
    cp "$DB_BACKUP" /home/user/events.db
    if [ "$HAD_OUTPUT" = 1 ]; then
        cp "$OUTPUT_BACKUP" /home/user/output.json
    else
        rm -f /home/user/output.json
    fi
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

import pytest

OUTPUT_PATH = '/home/user/output.json'
EXTRACT_SCRIPT = '/home/user/extract.py'
DB_PATH = '/home/user/events.db'
TRACE_DIR = '/tmp/extract_trace_hook'
TRACE_PATH = '/tmp/extract_sql_trace.jsonl'

HOOK_SOURCE = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("EXTRACT_SQL_TRACE")

def _log(kind, sql, params):
    if not _trace_path:
        return
    try:
        payload = {"kind": kind, "sql": str(sql), "params": params}
        with open(_trace_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload, default=repr) + "\\n")
    except Exception:
        pass

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)
    def execute(self, sql, parameters=()):
        _log("execute", sql, parameters)
        self._cursor.execute(sql, parameters)
        return self
    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        _log("executemany", sql, values)
        self._cursor.executemany(sql, values)
        return self
    def executescript(self, sql_script):
        _log("executescript", sql_script, None)
        self._cursor.executescript(sql_script)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)
    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)
    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, parameters=()):
        _log("execute", sql, parameters)
        return CursorProxy(self._connection.execute(sql, parameters))
    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        _log("executemany", sql, values)
        return CursorProxy(self._connection.executemany(sql, values))
    def executescript(self, sql_script):
        _log("executescript", sql_script, None)
        return CursorProxy(self._connection.executescript(sql_script))
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)
    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
'''


def _contains_number(value, expected):
    if isinstance(value, dict):
        return any(_contains_number(v, expected) for v in value.values())
    if isinstance(value, (list, tuple)):
        return any(_contains_number(v, expected) for v in value)
    return isinstance(value, (int, float)) and not isinstance(value, bool) and float(value) == float(expected)


def _validate_trace(threshold):
    assert os.path.isfile(TRACE_PATH), 'No SQLite execution trace was produced.'
    with open(TRACE_PATH, encoding='utf-8') as f:
        records = [json.loads(line) for line in f if line.strip()]

    assert len(records) == 1, f'Expected exactly one SQL execution, found {len(records)}.'
    record = records[0]
    assert record['kind'] == 'execute', 'The extraction must use one parameterized execute call.'
    sql = record['sql']
    upper = sql.upper()
    assert re.search(r'\b(ROW_NUMBER|RANK|DENSE_RANK)\s*\([^)]*\)\s*OVER\s*\(', upper), \
        'The SQL query must use a ranking window function.'
    assert re.search(r'\bAMOUNT\b[^)]]{0,200}\bDESC\b', upper), \
        'The window ordering must rank amount descending.'
    assert re.search(r'\bID\b[^)]]{0,200}\bDESC\b', upper), \
        'The window ordering must break ties by purchase id descending.'
    assert ('?' in sql or re.search(r'[:@$][A-Za-z_]\w*', sql)), \
        'The minimum amount must be represented by a SQL placeholder.'
    assert _contains_number(record.get('params'), threshold), \
        'The --min-amount value was not supplied as a bound SQL parameter.'


def _run_extract(threshold):
    os.makedirs(TRACE_DIR, exist_ok=True)
    with open(os.path.join(TRACE_DIR, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(HOOK_SOURCE)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = TRACE_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['EXTRACT_SQL_TRACE'] = TRACE_PATH
    result = subprocess.run(
        ['python3', EXTRACT_SCRIPT, '--min-amount', str(threshold)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=20,
    )
    assert result.returncode == 0, f'extract.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist after running extract.py.'
    _validate_trace(threshold)
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'File {OUTPUT_PATH} does not contain valid JSON: {exc}')


def _expected_from_database(threshold):
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        '''
        WITH ranked AS (
            SELECT p.id, p.user_id, p.amount, p.category,
                   ROW_NUMBER() OVER (
                       PARTITION BY p.user_id
                       ORDER BY p.amount DESC, p.id DESC
                   ) AS rn
            FROM purchases AS p
            WHERE p.amount >= ?
        )
        SELECT u.id, u.name, u.email, r.id, r.amount, r.category
        FROM ranked AS r
        JOIN users AS u ON u.id = r.user_id
        WHERE r.rn <= 2
        ORDER BY u.id ASC, r.amount DESC, r.id DESC
        ''',
        (threshold,),
    ).fetchall()
    conn.close()

    documents = []
    by_user = {}
    for user_id, name, email, purchase_id, amount, category in rows:
        if user_id not in by_user:
            document = {
                'user_id': user_id,
                'profile': {'name': name, 'email': email},
                'top_purchases': [],
            }
            by_user[user_id] = document
            documents.append(document)
        by_user[user_id]['top_purchases'].append({
            'purchase_id': purchase_id,
            'amount': amount,
            'category': category,
        })
    return documents


@pytest.fixture(scope='module')
def initial_data():
    return _run_extract(50.0)


def test_extract_script_exists():
    assert os.path.isfile(EXTRACT_SCRIPT), f'Extraction script {EXTRACT_SCRIPT} does not exist.'


def test_required_python_interfaces_are_used():
    with open(EXTRACT_SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=EXTRACT_SCRIPT)

    imports_argparse = any(
        (isinstance(node, ast.Import) and any(alias.name == 'argparse' for alias in node.names)) or
        isinstance(node, ast.ImportFrom) and node.module == 'argparse'
        for node in ast.walk(tree)
    )
    assert imports_argparse, 'extract.py must use argparse.'

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(
        (isinstance(call.func, ast.Attribute) and call.func.attr == 'ArgumentParser') or
        (isinstance(call.func, ast.Name) and call.func.id == 'ArgumentParser')
        for call in calls
    ), 'extract.py must construct an argparse.ArgumentParser.'

    min_amount_calls = [
        call for call in calls
        if isinstance(call.func, ast.Attribute) and call.func.attr == 'add_argument'
        and any(isinstance(arg, ast.Constant) and arg.value == '--min-amount' for arg in call.args)
    ]
    assert min_amount_calls, 'argparse must define --min-amount.'
    assert any(
        any(keyword.arg == 'type' and isinstance(keyword.value, ast.Name) and keyword.value.id == 'float'
            for keyword in call.keywords)
        for call in min_amount_calls
    ), '--min-amount must be parsed as a float.'

    assert any(
        isinstance(call.func, ast.Attribute) and call.func.attr == 'dump'
        and any(keyword.arg == 'indent' and isinstance(keyword.value, ast.Constant) and keyword.value.value == 2
                for keyword in call.keywords)
        for call in calls
    ), 'The output must be written using json.dump with indent=2.'


def test_output_json_exists(initial_data):
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist.'


def test_output_json_content(initial_data):
    data = initial_data
    expected_data = [
        {
            'user_id': 1,
            'profile': {'name': 'Alice', 'email': 'alice@example.com'},
            'top_purchases': [
                {'purchase_id': 103, 'amount': 200.0, 'category': 'furniture'},
                {'purchase_id': 102, 'amount': 120.0, 'category': 'electronics'},
            ],
        },
        {
            'user_id': 2,
            'profile': {'name': 'Bob', 'email': 'bob@example.com'},
            'top_purchases': [
                {'purchase_id': 106, 'amount': 60.0, 'category': 'books'},
                {'purchase_id': 105, 'amount': 60.0, 'category': 'clothing'},
            ],
        },
    ]
    assert isinstance(data, list), 'Output JSON must be a list of objects.'
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} users in the output, but found {len(data)}.'
    assert data == expected_data, 'The generated JSON does not match the expected nested document structure or content.'


def test_varied_thresholds_and_database_content(initial_data):
    token = secrets.randbelow(1000000)
    threshold = float(70 + secrets.randbelow(20))
    user_id = 900000 + token
    base_id = 8000000 + token * 10

    conn = sqlite3.connect(DB_PATH)
    conn.execute('INSERT INTO users VALUES (?, ?, ?)', (user_id, f'Dynamic {token}', f'dynamic{token}@example.test'))
    conn.execute('INSERT INTO users VALUES (?, ?, ?)', (user_id + 1, 'Below Threshold', 'below@example.test'))
    conn.executemany(
        'INSERT INTO purchases VALUES (?, ?, ?, ?, ?)',
        [
            (base_id + 1, user_id, threshold + 15.25, 'first-tie', '2025-01-01 00:00:00'),
            (base_id + 2, user_id, threshold + 15.25, 'second-tie', '2025-01-02 00:00:00'),
            (base_id + 3, user_id, threshold + 300.5, 'largest', '2025-01-03 00:00:00'),
            (base_id + 4, user_id, threshold - 0.25, 'below', '2025-01-04 00:00:00'),
            (base_id + 5, user_id + 1, threshold - 1.0, 'excluded-user', '2025-01-05 00:00:00'),
        ],
    )
    conn.commit()
    conn.close()

    for current_threshold in (threshold, threshold + 200.0):
        expected = _expected_from_database(current_threshold)
        actual = _run_extract(current_threshold)
        assert actual == expected, f'Incorrect extraction for --min-amount {current_threshold}.'
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

restore_state
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
