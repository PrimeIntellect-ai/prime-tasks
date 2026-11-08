#!/bin/bash
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import json
import sqlite3

_TRACE = '/tmp/quota_sql_trace.jsonl'
_real_connect = sqlite3.connect

def _log(sql):
    if isinstance(sql, str):
        with open(_TRACE, 'a', encoding='utf-8') as f:
            f.write(json.dumps(sql) + '\n')

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, '_cursor', cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

    def __iter__(self):
        return iter(self._cursor)

    def __enter__(self):
        self._cursor.__enter__()
        return self

    def __exit__(self, *args):
        return self._cursor.__exit__(*args)

    def execute(self, sql, *args, **kwargs):
        _log(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        _log(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        _log(sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self

class ConnectionProxy:
    def __init__(self, conn):
        object.__setattr__(self, '_conn', conn)

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def __setattr__(self, name, value):
        setattr(self._conn, name, value)

    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, *args):
        return self._conn.__exit__(*args)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._conn.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        _log(sql)
        return CursorProxy(self._conn.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        _log(sql)
        return CursorProxy(self._conn.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        _log(sql)
        return CursorProxy(self._conn.executescript(sql, *args, **kwargs))

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
SITE_EOF

cat << 'DB_EOF' > /tmp/create_quota_test_db.py
import os
import secrets
import sqlite3

path = '/home/user/hierarchy.db'
if os.path.exists(path):
    os.remove(path)

r = lambda: 10 + secrets.randbelow(90)
sizes = {i: r() for i in (40, 7, 90, 3, 22, 65, 12, 70)}

nodes = [
    (40, None, 'root_dynamic', 'dir', sizes[40]),
    (7, 40, 'alpha_dynamic', 'dir', sizes[7]),
    (90, 7, 'beta_dynamic', 'dir', sizes[90]),
    (3, 90, 'deep_file', 'file', sizes[3]),
    (22, 40, 'gamma_dynamic', 'dir', sizes[22]),
    (65, 22, 'side_file', 'file', sizes[65]),
    (12, 40, 'delta_dynamic', 'dir', sizes[12]),
    (70, 12, 'other_file', 'file', sizes[70]),
]

total90 = sizes[90] + sizes[3]
total7 = sizes[7] + total90
total22 = sizes[22] + sizes[65]
total12 = sizes[12] + sizes[70]
total40 = sizes[40] + total7 + total22 + total12

quotas = [
    (40, total40 - 1),
    (7, total7 - 1),
    (90, total90),
    (22, total22 + 1),
    (12, total12 - 1),
    (3, 0),
]

conn = sqlite3.connect(path)
c = conn.cursor()
c.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, type TEXT, local_size INTEGER)')
c.execute('CREATE TABLE quotas (node_id INTEGER PRIMARY KEY, max_size INTEGER)')
c.executemany('INSERT INTO nodes VALUES (?,?,?,?,?)', nodes)
c.executemany('INSERT INTO quotas VALUES (?,?)', quotas)
conn.commit()
conn.close()
os.chmod(path, 0o666)
DB_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import pytest

VIOLATIONS_CSV = '/home/user/violations.csv'
DB_PATH = '/home/user/hierarchy.db'
SCRIPT_PATH = '/home/user/check_quotas.py'
TRACE_PATH = '/tmp/quota_sql_trace.jsonl'

QUERY = """
WITH RECURSIVE descendants AS (
    SELECT id as root_id, id as node_id, local_size
    FROM nodes
    UNION ALL
    SELECT d.root_id, n.id, n.local_size
    FROM descendants d
    JOIN nodes n ON n.parent_id = d.node_id
)
SELECT n.id, n.name, SUM(d.local_size) as total_size, q.max_size
FROM nodes n
JOIN descendants d ON n.id = d.root_id
JOIN quotas q ON n.id = q.node_id
WHERE n.type = 'dir'
GROUP BY n.id, n.name, q.max_size
HAVING total_size > q.max_size
ORDER BY n.id ASC;
"""

def expected_rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute(QUERY).fetchall()
    finally:
        conn.close()

def test_script_exists_and_is_python():
    assert os.path.exists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    with open(SCRIPT_PATH, 'rb') as f:
        source = f.read()
    compile(source, SCRIPT_PATH, 'exec')

def test_executed_recursive_cte_produces_violations():
    assert os.path.isfile(TRACE_PATH), 'The script did not execute any traced SQLite statements.'
    with open(TRACE_PATH, encoding='utf-8') as f:
        statements = [json.loads(line) for line in f if line.strip()]

    recursive = [s for s in statements if re.search(r'\bWITH\s+RECURSIVE\b', s, re.I)]
    assert recursive, 'The script did not execute a recursive CTE.'

    expected = expected_rows()
    matching = []
    conn = sqlite3.connect(DB_PATH)
    try:
        for statement in recursive:
            try:
                rows = conn.execute(statement).fetchall()
            except sqlite3.Error:
                continue
            if rows == expected:
                matching.append(statement)
    finally:
        conn.close()

    assert matching, 'No executed recursive CTE computed the required filtered, quota-joined result.'

def test_violations_csv_exists():
    assert os.path.exists(VIOLATIONS_CSV), f"Expected output file {VIOLATIONS_CSV} does not exist."
    assert os.path.isfile(VIOLATIONS_CSV), f"{VIOLATIONS_CSV} is not a file."

def test_violations_csv_contents():
    # Recalculate expected results to be robust
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    query = """
    WITH RECURSIVE descendants AS (
        SELECT id as root_id, id as node_id, local_size
        FROM nodes
        UNION ALL
        SELECT d.root_id, n.id, n.local_size
        FROM descendants d
        JOIN nodes n ON n.parent_id = d.node_id
    )
    SELECT n.id, n.name, SUM(d.local_size) as total_size, q.max_size
    FROM nodes n
    JOIN descendants d ON n.id = d.root_id
    JOIN quotas q ON n.id = q.node_id
    WHERE n.type = 'dir'
    GROUP BY n.id, n.name, q.max_size
    HAVING total_size > q.max_size
    ORDER BY n.id ASC;
    """
    c.execute(query)
    expected_rows = c.fetchall()
    conn.close()

    expected_csv_lines = [
        f"{row[0]},{row[1]},{row[2]},{row[3]}" for row in expected_rows
    ]

    with open(VIOLATIONS_CSV, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_csv_lines), \
        f"Expected {len(expected_csv_lines)} rows in CSV, found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_csv_lines)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

python3 /tmp/create_quota_test_db.py
DB_STATUS=$?
rm -f /home/user/violations.csv /tmp/quota_sql_trace.jsonl
PYTHONPATH=/tmp python3 /home/user/check_quotas.py
SCRIPT_STATUS=$?
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
TEST_STATUS=$?

if [ "$DB_STATUS" -eq 0 ] && [ "$SCRIPT_STATUS" -eq 0 ] && [ "$TEST_STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
