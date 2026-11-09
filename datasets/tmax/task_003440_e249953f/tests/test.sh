#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import pickle
import random
import re
import sqlite3
import subprocess
import sys

import pytest

DB_PATH = '/home/user/routing.db'
JSON_PATH = '/home/user/top_paths.json'
SCRIPT_PATH = '/home/user/optimize_and_query.py'
TRACE_PATH = '/tmp/sql_trace.pkl'

ORIGINAL_NODES = [
    (1, 'Router_START', 'active'),
    (2, 'Router_A', 'active'),
    (3, 'Router_B', 'offline'),
    (4, 'Router_C', 'active'),
    (5, 'Router_D', 'active'),
    (6, 'Router_END', 'active'),
]
ORIGINAL_EDGES = [
    (1, 2, 10.0), (1, 4, 15.0), (1, 3, 5.0),
    (2, 4, 2.0), (2, 5, 8.0), (4, 6, 10.0),
    (5, 6, 3.0), (4, 5, 1.0), (3, 6, 2.0),
]
ORIGINAL_EXPECTED = [
    {'path_names': 'Router_START,Router_A,Router_C,Router_D,Router_END', 'total_weight': 16.0, 'hop_count': 4},
    {'path_names': 'Router_START,Router_C,Router_D,Router_END', 'total_weight': 19.0, 'hop_count': 3},
    {'path_names': 'Router_START,Router_A,Router_D,Router_END', 'total_weight': 21.0, 'hop_count': 3},
]


def load_output():
    assert os.path.exists(JSON_PATH), f'Output file {JSON_PATH} does not exist.'
    assert os.path.isfile(JSON_PATH), f'Path {JSON_PATH} is not a file.'
    try:
        with open(JSON_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {JSON_PATH} is not valid JSON.')


def assert_results(actual, expected):
    assert isinstance(actual, list), 'JSON output must be a list of objects.'
    assert len(actual) == 3, f'Expected exactly 3 paths, got {len(actual)}.'
    for i, wanted in enumerate(expected):
        got = actual[i]
        assert isinstance(got, dict), f'Result {i+1} is not an object.'
        for key in ('path_names', 'total_weight', 'hop_count'):
            assert key in got, f"Missing '{key}' in result {i+1}."
        assert got['path_names'] == wanted['path_names'], f"Result {i+1} 'path_names' mismatch."
        assert float(got['total_weight']) == pytest.approx(float(wanted['total_weight']), abs=1e-8)
        assert int(got['hop_count']) == int(wanted['hop_count'])


def assert_optimal_index():
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        assert conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_bad'").fetchone() is None, "The bad index 'idx_bad' was not dropped."
        indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'").fetchall()
        assert len(indexes) == 1, f"Expected exactly 1 index on 'edges', found {len(indexes)}."
        name = indexes[0][0]
        columns = conn.execute('PRAGMA index_info(%s)' % json.dumps(name)).fetchall()
        assert len(columns) >= 2, f'Index {name} is not composite.'
        ordered = [row[2] for row in sorted(columns, key=lambda row: row[0])]
        assert ordered[0] == 'source_id', f"The optimal index must start with 'source_id', but starts with '{ordered[0]}'."
        assert ordered[1] == 'target_id', f"The second index column must be 'target_id', but is '{ordered[1]}'."
    finally:
        conn.close()


def make_dynamic_database():
    rng = random.SystemRandom()
    suffix = rng.randrange(10**8, 10**9)
    names = {
        1: 'Router_START', 30: 'Router_END',
        2: f'Alpha_{suffix}', 3: f'Beta_{suffix}', 4: f'Gamma_{suffix}',
        5: f'Delta_{suffix}', 6: f'Epsilon_{suffix}', 7: f'Zeta_{suffix}',
        8: f'Eta_{suffix}', 20: f'Offline_{suffix}',
        10: f'Long1_{suffix}', 11: f'Long2_{suffix}', 12: f'Long3_{suffix}',
        13: f'Long4_{suffix}', 14: f'Long5_{suffix}', 15: f'Long6_{suffix}',
        16: f'Long7_{suffix}',
    }
    nodes = [(node_id, name, 'offline' if node_id == 20 else 'active') for node_id, name in names.items()]
    pairs = [
        (1, 2), (2, 30),
        (1, 3), (3, 4), (4, 30),
        (1, 5), (5, 6), (6, 7), (7, 30),
        (1, 8), (8, 30),
        (1, 20), (20, 30),
        (1, 10), (10, 11), (11, 12), (12, 13), (13, 14),
        (14, 15), (15, 16), (16, 30),
    ]
    # Random, high-resolution positive weights make hardcoded answers unusable and ties negligible.
    edges = [(a, b, rng.randrange(1000, 50000) / 997.0 + i / 1000003.0) for i, (a, b) in enumerate(pairs, 1)]

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, status TEXT)')
    conn.execute('CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight REAL)')
    conn.executemany('INSERT INTO nodes VALUES (?, ?, ?)', nodes)
    conn.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
    conn.execute('CREATE INDEX idx_bad ON edges (weight, target_id)')
    conn.commit()
    conn.close()

    status = {row[0]: row[2] for row in nodes}
    graph = {}
    for source, target, weight in edges:
        graph.setdefault(source, []).append((target, weight))
    paths = []

    def visit(node, path, weight, depth):
        if node == 30:
            paths.append({
                'path_names': ','.join(names[x] for x in path),
                'total_weight': weight,
                'hop_count': depth,
            })
            return
        if depth == 7:
            return
        for target, edge_weight in graph.get(node, []):
            if status[target] == 'active':
                visit(target, path + [target], weight + edge_weight, depth + 1)

    visit(1, [1], 0.0, 0)
    paths.sort(key=lambda item: item['total_weight'])
    return paths[:3], sorted(nodes), sorted(edges)


def run_with_trace():
    runner = r'''
import json
import pickle
import runpy
import sqlite3 as real_sqlite3
import sys
import types

trace = []

class Cursor:
    def __init__(self, inner): self._inner = inner
    def execute(self, sql, parameters=()):
        trace.append((sql, parameters))
        self._inner.execute(sql, parameters)
        return self
    def executemany(self, sql, seq):
        values = list(seq)
        trace.append((sql, values))
        self._inner.executemany(sql, values)
        return self
    def executescript(self, sql):
        trace.append((sql, ()))
        self._inner.executescript(sql)
        return self
    def __iter__(self): return iter(self._inner)
    def __enter__(self): return self
    def __exit__(self, *args): self.close()
    def __getattr__(self, name): return getattr(self._inner, name)

class Connection:
    def __init__(self, inner): self._inner = inner
    def cursor(self, *args, **kwargs): return Cursor(self._inner.cursor(*args, **kwargs))
    def execute(self, sql, parameters=()):
        trace.append((sql, parameters))
        return Cursor(self._inner.execute(sql, parameters))
    def executemany(self, sql, seq):
        values = list(seq)
        trace.append((sql, values))
        return Cursor(self._inner.executemany(sql, values))
    def executescript(self, sql):
        trace.append((sql, ()))
        return Cursor(self._inner.executescript(sql))
    def __enter__(self):
        self._inner.__enter__()
        return self
    def __exit__(self, *args): return self._inner.__exit__(*args)
    def __getattr__(self, name): return getattr(self._inner, name)

def connect(*args, **kwargs): return Connection(real_sqlite3.connect(*args, **kwargs))

fake = types.ModuleType('sqlite3')
fake.__dict__.update(real_sqlite3.__dict__)
fake.connect = connect
sys.modules['sqlite3'] = fake
try:
    runpy.run_path('/home/user/optimize_and_query.py', run_name='__main__')
finally:
    with open('/tmp/sql_trace.pkl', 'wb') as f:
        pickle.dump(trace, f)
'''
    subprocess.run([sys.executable, '-c', runner], check=True, timeout=25, cwd='/home/user')


def test_complete_solution():
    assert os.path.exists(SCRIPT_PATH), f'Required script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a regular file.'
    assert os.path.getsize(SCRIPT_PATH) > 0, f'{SCRIPT_PATH} is empty.'

    # Execute the submitted artifact against the supplied database before retaining
    # all of the original output and index assertions.
    subprocess.run([sys.executable, SCRIPT_PATH], check=True, timeout=25, cwd='/home/user')
    assert_results(load_output(), ORIGINAL_EXPECTED)
    assert_optimal_index()

    conn = sqlite3.connect(DB_PATH)
    try:
        assert conn.execute('SELECT id,name,status FROM nodes ORDER BY id').fetchall() == ORIGINAL_NODES
        assert conn.execute('SELECT source_id,target_id,weight FROM edges ORDER BY rowid').fetchall() == ORIGINAL_EDGES
    finally:
        conn.close()

    expected, original_nodes, original_edges = make_dynamic_database()
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)
    run_with_trace()

    # Behavioral checks use fresh names and weights and independently derive the answer.
    assert_results(load_output(), expected)
    assert_optimal_index()
    conn = sqlite3.connect(DB_PATH)
    try:
        after_nodes = sorted(conn.execute('SELECT id,name,status FROM nodes').fetchall())
        after_edges = sorted(conn.execute('SELECT source_id,target_id,weight FROM edges').fetchall())
        assert after_nodes == original_nodes, 'The script modified data in the nodes table.'
        assert after_edges == original_edges, 'The script modified data in the edges table.'
    finally:
        conn.close()

    assert os.path.isfile(TRACE_PATH), 'No SQL execution trace was produced.'
    with open(TRACE_PATH, 'rb') as f:
        trace = pickle.load(f)
    recursive = [(sql, params) for sql, params in trace
                 if isinstance(sql, str) and re.search(r'\bWITH\s+RECURSIVE\b', sql, re.I)]
    assert len(recursive) == 1, f'Expected exactly one WITH RECURSIVE query, observed {len(recursive)}.'
    sql, params = recursive[0]
    lowered = sql.lower()
    assert re.search(r'\bnodes\b', lowered), 'Recursive query does not use nodes.'
    assert re.search(r'\bedges\b', lowered), 'Recursive query does not use edges.'
    assert 'status' in lowered, 'Active-node filtering must be performed in the recursive SQL query.'
    assert re.search(r'order\s+by[\s\S]*total_weight', lowered), 'The SQL query must order by total_weight.'
    assert re.search(r'limit\s+(?:3|\?)', lowered), 'The SQL query must apply LIMIT 3.'

    # Re-execute the captured recursive statement itself. Its result, not merely the
    # script's JSON, must contain the independently derived top paths.
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.execute(sql, params)
        column_names = [item[0] for item in cur.description]
        assert all(key in column_names for key in ('path_names', 'total_weight', 'hop_count')), 'Recursive query must return all required aggregate columns.'
        rows = [dict(zip(column_names, row)) for row in cur.fetchall()]
    finally:
        conn.close()
    assert_results(rows, expected)
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
