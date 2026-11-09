#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -f /tmp/optimize_sql_trace.jsonl
mkdir -p /tmp/verifier_hook
cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import sqlite3

_TRACE_PATH = '/tmp/optimize_sql_trace.jsonl'
_real_connect = sqlite3.connect

def _safe(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, dict):
        return {str(k): _safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_safe(v) for v in value]
    return repr(value)

def _log(kind, sql, parameters=None):
    event = {'kind': kind, 'sql': str(sql), 'parameters': _safe(parameters)}
    with open(_TRACE_PATH, 'a', encoding='utf-8') as f:
        f.write(json.dumps(event) + '\n')

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=()):
        _log('execute', sql, parameters)
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        params = list(seq_of_parameters)
        _log('executemany', sql, params)
        self._cursor.executemany(sql, params)
        return self

    def executescript(self, sql_script):
        _log('executescript', sql_script, None)
        self._cursor.executescript(sql_script)
        return self

    def __iter__(self):
        return self

    def __next__(self):
        return next(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        _log('execute', sql, parameters)
        return CursorProxy(self._connection.execute(sql, parameters))

    def executemany(self, sql, seq_of_parameters):
        params = list(seq_of_parameters)
        _log('executemany', sql, params)
        return CursorProxy(self._connection.executemany(sql, params))

    def executescript(self, sql_script):
        _log('executescript', sql_script, None)
        return CursorProxy(self._connection.executescript(sql_script))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        if name == '_connection':
            object.__setattr__(self, name, value)
        else:
            setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import sqlite3
import subprocess
import pytest

DB_PATH = '/home/user/ecommerce.db'
OPTIMIZE_PY_PATH = '/home/user/optimize.py'
JSON_OUTPUT_PATH = '/home/user/top_customers.json'
QUERY_PLAN_PATH = '/home/user/query_plan.txt'
TRACE_PATH = '/tmp/optimize_sql_trace.jsonl'
HOOK_PATH = '/tmp/verifier_hook'

def _contains_five(value):
    if value == 5 or value == '5':
        return True
    if isinstance(value, list):
        return any(_contains_five(v) for v in value)
    if isinstance(value, dict):
        return any(_contains_five(v) for v in value.values())
    return False

def _is_parameterized(sql):
    return re.search(r'\?|[:@$][A-Za-z_][A-Za-z0-9_]*', sql) is not None

def _is_required_query(sql):
    upper = sql.upper()
    return (
        re.search(r'\bWITH\b', upper) is not None
        and re.search(r'\bSUM\s*\(', upper) is not None
        and re.search(r'\bRANK\s*\(', upper) is not None
        and re.search(r'\bOVER\s*\(', upper) is not None
    )

def test_run_optimize_script_and_sql():
    assert os.path.exists(OPTIMIZE_PY_PATH), f"Script missing at {OPTIMIZE_PY_PATH}"
    assert os.path.isfile(OPTIMIZE_PY_PATH), f"{OPTIMIZE_PY_PATH} is not a file"

    for path in (JSON_OUTPUT_PATH, QUERY_PLAN_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = HOOK_PATH if not old_pythonpath else HOOK_PATH + os.pathsep + old_pythonpath
    result = subprocess.run(
        ['python3', OPTIMIZE_PY_PATH],
        cwd='/home/user', env=env, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"optimize.py failed with exit code {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(TRACE_PATH), "The script did not execute SQL through a Python sqlite3 connection."

    with open(TRACE_PATH, encoding='utf-8') as f:
        events = [json.loads(line) for line in f if line.strip()]

    create_indexes = [e for e in events if re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', e['sql'], re.I)]
    assert any(re.search(r'\bORDERS\b', e['sql'], re.I) and re.search(r'\bCUSTOMER_ID\b', e['sql'], re.I)
               for e in create_indexes), "optimize.py did not execute creation of an orders(customer_id) index."

    data_queries = [e for e in events
                    if not re.match(r'^\s*EXPLAIN\s+QUERY\s+PLAN\b', e['sql'], re.I)
                    and _is_required_query(e['sql'])]
    assert any(_is_parameterized(e['sql']) and _contains_five(e.get('parameters')) for e in data_queries), (
        "optimize.py did not execute a parameterized CTE query using SUM and RANK() OVER with limit 5."
    )

    explain_queries = [e for e in events if re.match(r'^\s*EXPLAIN\s+QUERY\s+PLAN\b', e['sql'], re.I)]
    assert any(_is_required_query(e['sql']) and _is_parameterized(e['sql'])
               and _contains_five(e.get('parameters')) for e in explain_queries), (
        "optimize.py did not execute EXPLAIN QUERY PLAN on the parameterized optimized query."
    )

def test_optimize_script_exists():
    assert os.path.exists(OPTIMIZE_PY_PATH), f"Script missing at {OPTIMIZE_PY_PATH}"
    assert os.path.isfile(OPTIMIZE_PY_PATH), f"{OPTIMIZE_PY_PATH} is not a file"

def test_index_created():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='orders';")
    indexes = cursor.fetchall()
    conn.close()

    user_indexes = [idx for idx in indexes if idx[1] is not None]
    assert len(user_indexes) > 0, "No custom index was created on the 'orders' table."

    index_sql = " ".join([idx[1].lower() for idx in user_indexes])
    assert "customer_id" in index_sql, "The created index does not appear to be on 'customer_id'."

def test_top_customers_json():
    assert os.path.exists(JSON_OUTPUT_PATH), f"JSON output missing at {JSON_OUTPUT_PATH}"

    with open(JSON_OUTPUT_PATH, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_OUTPUT_PATH} does not contain valid JSON.")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT c.name, SUM(o.amount) as total_amount, RANK() OVER(ORDER BY SUM(o.amount) DESC) as rank
        FROM customers c JOIN orders o ON c.id = o.customer_id
        GROUP BY c.id
        ORDER BY rank LIMIT 5
    ''')

    expected = [{"name": row[0], "total_amount": row[1], "rank": row[2]} for row in cursor.fetchall()]
    conn.close()

    assert isinstance(actual, list), "JSON output should be a list of dictionaries."
    assert len(actual) == len(expected), f"Expected {len(expected)} items, got {len(actual)}."

    for i in range(len(expected)):
        assert actual[i].get("name") == expected[i]["name"], f"Mismatch in name at rank {i+1}"
        assert abs(actual[i].get("total_amount", 0) - expected[i]["total_amount"]) < 1e-5, f"Mismatch in total_amount at rank {i+1}"
        assert actual[i].get("rank") == expected[i]["rank"], f"Mismatch in rank at rank {i+1}"

def test_query_plan_txt():
    assert os.path.exists(QUERY_PLAN_PATH), f"Query plan output missing at {QUERY_PLAN_PATH}"

    with open(QUERY_PLAN_PATH, 'r') as f:
        content = f.read().upper()

    assert content.strip(), "Query plan file is empty."

    has_scan = "SCAN" in content
    has_search = "SEARCH" in content
    has_covering = "COVERING INDEX" in content

    assert has_scan or has_search or has_covering, "Query plan output does not contain expected EXPLAIN QUERY PLAN keywords (SCAN, SEARCH, etc.)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
