#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/sql_audit
cat <<'PY_EOF' > /tmp/sql_audit/sitecustomize.py
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_log_path = os.environ.get('SQL_AUDIT_LOG')

def _record(kind, sql, args):
    if not _log_path:
        return
    try:
        params = args[0] if args else None
        entry = {'kind': kind, 'sql': str(sql), 'params': params}
        line = json.dumps(entry, default=repr)
        with open(_log_path, 'a', encoding='utf-8') as f:
            f.write(line + '\n')
    except Exception:
        pass

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, *args):
        _record('execute', sql, args)
        self._cursor.execute(sql, *args)
        return self

    def executemany(self, sql, *args):
        _record('executemany', sql, args)
        self._cursor.executemany(sql, *args)
        return self

    def executescript(self, sql):
        _record('executescript', sql, ())
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, conn):
        self._conn = conn

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._conn.cursor(*args, **kwargs))

    def execute(self, sql, *args):
        _record('connection.execute', sql, args)
        return CursorProxy(self._conn.execute(sql, *args))

    def executemany(self, sql, *args):
        _record('connection.executemany', sql, args)
        return CursorProxy(self._conn.executemany(sql, *args))

    def executescript(self, sql):
        _record('connection.executescript', sql, ())
        return CursorProxy(self._conn.executescript(sql))

    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, *args):
        return self._conn.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._conn, name)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import re
import sqlite3
import subprocess
import sys

DB_PATH = '/home/user/corporate_audit.db'
SCRIPT_PATH = '/home/user/detect_cycle.py'
CYCLE_TXT_PATH = '/home/user/cycle.txt'
INDEX_SCHEMA_TXT_PATH = '/home/user/index_schema.txt'
AUDIT_DIR = '/tmp/sql_audit'


def create_database(edges):
    for suffix in ('', '-wal', '-shm'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE ownership_graph (owner_id INTEGER, subsidiary_id INTEGER)')
    conn.executemany('INSERT INTO ownership_graph VALUES (?, ?)', edges)
    conn.commit()
    conn.close()
    os.chmod(DB_PATH, 0o777)


def shortest_cycle(edges):
    graph = {}
    for owner, subsidiary in edges:
        graph.setdefault(owner, []).append(subsidiary)
    queue = [(1001, [1001])]
    while queue:
        node, path = queue.pop(0)
        for nxt in graph.get(node, []):
            if nxt == 1001 and len(path) > 1:
                return path + [1001]
            if nxt not in path:
                queue.append((nxt, path + [nxt]))
    raise AssertionError('Verifier-generated graph unexpectedly has no cycle')


def load_log(path):
    entries = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            entries.append(json.loads(line))
    return entries


def row_contains_path(row, expected):
    for value in row:
        if value is None:
            continue
        numbers = [int(x) for x in re.findall(r'(?<!\d)\d+(?!\d)', str(value))]
        if numbers == expected:
            return True
    return False


def replay_recursive_query(entry, expected):
    conn = sqlite3.connect(DB_PATH)
    try:
        params = entry.get('params')
        if params is None:
            cursor = conn.execute(entry['sql'])
        elif isinstance(params, list):
            cursor = conn.execute(entry['sql'], tuple(params))
        else:
            cursor = conn.execute(entry['sql'], params)
        first = cursor.fetchone()
    finally:
        conn.close()
    assert first is not None, 'The recursive CTE returned no result row.'
    assert row_contains_path(first, expected), (
        'The recursive CTE itself did not return the shortest cycle in its first result row; '
        'the traversal/selection must be performed in SQL, not reconstructed from fetched rows.'
    )


def verify_logged_sql(entries, expected):
    recursive = [e for e in entries if re.search(r'\bWITH\s+RECURSIVE\b', e['sql'], re.I)]
    assert len(recursive) == 1, f'Expected exactly one executed recursive CTE query, found {len(recursive)}.'

    query = recursive[0]['sql']
    upper = query.upper()
    assert 'OWNERSHIP_GRAPH' in upper, 'The recursive CTE does not query ownership_graph.'
    assert re.search(r'\bUNION(?:\s+ALL)?\b', upper), 'The CTE does not contain a recursive UNION term.'
    match = re.search(r'\bWITH\s+RECURSIVE\s+([A-Za-z_]\w*)', query, re.I)
    assert match and len(re.findall(r'\b' + re.escape(match.group(1)) + r'\b', query, re.I)) >= 2, (
        'The declared recursive CTE is not referenced by its recursive/query terms.'
    )

    # Reject fetching ownership_graph through a separate non-recursive SELECT for Python traversal.
    for entry in entries:
        sql_upper = entry['sql'].upper()
        if entry is not recursive[0] and 'OWNERSHIP_GRAPH' in sql_upper and re.search(r'\bSELECT\b', sql_upper):
            raise AssertionError('ownership_graph was read by a separate non-recursive SELECT.')

    creates = [e for e in entries if re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', e['sql'], re.I)]
    assert any('IDX_OWNER_SUB' in e['sql'].upper() and 'OWNER_ID' in e['sql'].upper() for e in creates), (
        'detect_cycle.py did not execute creation of idx_owner_sub on owner_id.'
    )
    schema_reads = [e for e in entries if 'SQLITE_MASTER' in e['sql'].upper() and re.search(r'\bSELECT\b', e['sql'], re.I)]
    assert schema_reads, 'detect_cycle.py did not retrieve the index SQL from sqlite_master.'

    replay_recursive_query(recursive[0], expected)


def run_case(edges, case_number):
    create_database(edges)
    for path in (CYCLE_TXT_PATH, INDEX_SCHEMA_TXT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    log_path = f'/tmp/sql_audit_case_{case_number}.jsonl'
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    env['PYTHONPATH'] = AUDIT_DIR + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['SQL_AUDIT_LOG'] = log_path
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f'detect_cycle.py failed: {result.stderr}'
    assert os.path.isfile(log_path), 'No SQL execution was observed from detect_cycle.py.'

    expected = shortest_cycle(edges)
    expected_text = ','.join(map(str, expected))
    assert os.path.isfile(CYCLE_TXT_PATH), f'Output file not found at {CYCLE_TXT_PATH}'
    with open(CYCLE_TXT_PATH, encoding='utf-8') as f:
        content = f.read().strip()
    assert content == expected_text, f"Expected cycle path '{expected_text}', but found '{content}'"

    verify_logged_sql(load_log(log_path), expected)


def test_complete_solution():
    assert os.path.isfile(SCRIPT_PATH), f'Python script not found at {SCRIPT_PATH}'
    assert os.path.isfile(DB_PATH), f'Database file not found at {DB_PATH}'
    with open(SCRIPT_PATH, encoding='utf-8') as f:
        ast.parse(f.read(), filename=SCRIPT_PATH)

    rng = random.SystemRandom()
    ids = rng.sample([n for n in range(1200, 900000) if n != 1001], 14)
    case1 = [
        (1001, ids[0]), (ids[0], ids[1]), (ids[1], 1001),
        (1001, ids[2]), (ids[2], ids[3]), (ids[3], ids[4]), (ids[4], 1001),
        (1001, ids[5]), (ids[5], ids[6]),
        (ids[7], ids[8]), (ids[8], ids[9]),
    ]
    case2 = [
        (1001, ids[10]), (ids[10], ids[11]), (ids[11], ids[12]), (ids[12], ids[13]), (ids[13], 1001),
        (1001, ids[0]), (ids[0], ids[1]), (ids[1], ids[2]), (ids[2], ids[3]), (ids[3], ids[4]), (ids[4], 1001),
        (1001, ids[5]), (ids[5], ids[6]),
    ]
    run_case(case1, 1)
    run_case(case2, 2)

    assert os.path.isfile(INDEX_SCHEMA_TXT_PATH), f'Index schema file not found at {INDEX_SCHEMA_TXT_PATH}'
    with open(INDEX_SCHEMA_TXT_PATH, encoding='utf-8') as f:
        schema_content = f.read().strip()
    assert 'CREATE INDEX' in schema_content.upper(), "The file does not contain a 'CREATE INDEX' statement."
    assert 'IDX_OWNER_SUB' in schema_content.upper(), "The file does not contain the index name 'idx_owner_sub'."

    conn = sqlite3.connect(DB_PATH)
    result = conn.execute("SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_owner_sub'").fetchone()
    assert result is not None, "Index 'idx_owner_sub' was not found in the database."
    actual_sql = result[0]
    assert 'OWNER_ID' in actual_sql.upper(), "The index does not appear to index owner_id."
    index_info = conn.execute("PRAGMA index_info('idx_owner_sub')").fetchall()
    conn.close()
    assert index_info, "Could not retrieve index info for 'idx_owner_sub'."
    indexed_columns = [row[2] for row in index_info]
    assert indexed_columns[0] == 'owner_id', f"Expected first indexed column owner_id, got {indexed_columns[0]!r}."
    assert schema_content == actual_sql.strip(), 'index_schema.txt does not exactly match sqlite_master.sql.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
