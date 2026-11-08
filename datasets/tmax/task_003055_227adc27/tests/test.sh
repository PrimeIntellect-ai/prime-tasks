#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
from collections import deque

import pytest

DB_PATH = '/home/user/graph_data/knowledge.db'
CSV_PATH = '/home/user/graph_data/new_edges.csv'
JSON_PATH = '/home/user/graph_data/downstream_nodes.json'
SCRIPT_PATH = '/home/user/process_graph.py'


def assert_unique_index(conn):
    rows = conn.execute("PRAGMA index_list('edges')").fetchall()
    matches = [row for row in rows if row[1] == 'idx_unique_edges']
    assert matches, "Unique index 'idx_unique_edges' was not created on the edges table."
    assert matches[0][2] == 1, "Index 'idx_unique_edges' exists but is not UNIQUE."
    assert matches[0][4] == 0, "Index 'idx_unique_edges' must not be a partial index."

    columns = conn.execute("PRAGMA index_info('idx_unique_edges')").fetchall()
    assert [row[2] for row in columns] == ['source', 'target'], \
        "Index 'idx_unique_edges' must cover (source, target), in that order."


def test_01_script_exists_and_is_python():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"
    with open(SCRIPT_PATH, 'rb') as f:
        source = f.read()
    assert source, "process_graph.py is empty."
    compile(source, SCRIPT_PATH, 'exec')


def test_02_unique_index_created():
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_unique_edges'")
        idx = cur.fetchone()
        assert idx is not None, "Unique index 'idx_unique_edges' was not created on the edges table."
        assert_unique_index(conn)
    finally:
        conn.close()


def test_03_edges_table_state():
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT count(*) FROM edges")
    count = cur.fetchone()[0]
    assert count == 7, f"Expected exactly 7 edges after cleaning and upserting, but found {count}."

    cur.execute("SELECT source, target, COUNT(*) FROM edges GROUP BY source, target HAVING COUNT(*) > 1")
    duplicates = cur.fetchall()
    assert len(duplicates) == 0, "Stale rows were not properly deleted. Duplicate (source, target) pairs still exist."

    cur.execute("SELECT weight, updated_at FROM edges WHERE source='ROOT_42' AND target='N_2'")
    res = cur.fetchone()
    assert res is not None, "Edge ROOT_42 -> N_2 is missing."
    assert res[0] == 3.0 and res[1] == 200, f"Edge ROOT_42 -> N_2 was not updated correctly. Expected weight 3.0, updated_at 200, got {res}."

    cur.execute("SELECT weight, updated_at FROM edges WHERE source='N_1' AND target='N_3'")
    res = cur.fetchone()
    assert res is not None, "Edge N_1 -> N_3 is missing."
    assert res[0] == 2.0 and res[1] == 150, f"Edge N_1 -> N_3 was incorrectly updated with stale data. Expected weight 2.0, updated_at 150, got {res}."

    cur.execute("SELECT weight, updated_at FROM edges WHERE source='N_4' AND target='N_6'")
    res = cur.fetchone()
    assert res is not None, "New edge N_4 -> N_6 from CSV was not inserted."
    assert res[0] == 1.0 and res[1] == 300, f"New edge N_4 -> N_6 has incorrect data. Expected weight 1.0, updated_at 300, got {res}."

    conn.close()


def test_04_json_output():
    assert os.path.exists(JSON_PATH), f"JSON output file missing at {JSON_PATH}"

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file downstream_nodes.json is not a valid JSON.")

    expected = {
        "N_1": 1,
        "N_2": 1,
        "N_3": 2,
        "N_5": 2,
        "N_4": 3,
        "ROOT_42": 3,
        "N_6": 4
    }

    assert isinstance(data, dict), "JSON root should be a dictionary."

    for node, hops in expected.items():
        assert node in data, f"Node {node} is missing from the output JSON."
        assert data[node] == hops, f"Incorrect hop count for {node}. Expected {hops}, got {data[node]}."

    for node in data:
        assert node in expected, f"Unexpected node {node} found in the output JSON."


def make_launcher(path):
    launcher = r'''
import json
import runpy
import sqlite3 as real_sqlite3
import sys
import types

script_path, trace_path = sys.argv[1], sys.argv[2]
events = []
_MISSING = object()


def record(kind, sql, parameters):
    events.append({
        "kind": kind,
        "sql": str(sql),
        "parameterized": parameters is not _MISSING,
    })


class CursorProxy:
    def __init__(self, inner):
        self._inner = inner

    def execute(self, sql, parameters=_MISSING):
        record("execute", sql, parameters)
        if parameters is _MISSING:
            self._inner.execute(sql)
        else:
            self._inner.execute(sql, parameters)
        return self

    def executemany(self, sql, seq):
        record("executemany", sql, seq)
        self._inner.executemany(sql, seq)
        return self

    def executescript(self, sql):
        record("executescript", sql, _MISSING)
        self._inner.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)


class ConnectionProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._inner.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_MISSING):
        record("execute", sql, parameters)
        if parameters is _MISSING:
            cur = self._inner.execute(sql)
        else:
            cur = self._inner.execute(sql, parameters)
        return CursorProxy(cur)

    def executemany(self, sql, seq):
        record("executemany", sql, seq)
        return CursorProxy(self._inner.executemany(sql, seq))

    def executescript(self, sql):
        record("executescript", sql, _MISSING)
        return CursorProxy(self._inner.executescript(sql))

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name == "_inner":
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)


def connect(*args, **kwargs):
    return ConnectionProxy(real_sqlite3.connect(*args, **kwargs))


proxy = types.ModuleType("sqlite3")
proxy.__dict__.update(real_sqlite3.__dict__)
proxy.connect = connect
sys.modules["sqlite3"] = proxy
sys.argv = [script_path]

try:
    runpy.run_path(script_path, run_name="__main__")
finally:
    with open(trace_path, "w") as f:
        json.dump(events, f)
'''
    with open(path, 'w') as f:
        f.write(launcher)


def derived_hops(final_edges):
    adjacency = {}
    for source, target in final_edges:
        adjacency.setdefault(source, []).append(target)

    distances = {'ROOT_42': 0}
    queue = deque(['ROOT_42'])
    while queue:
        source = queue.popleft()
        for target in adjacency.get(source, []):
            if target == 'ROOT_42':
                continue
            if target not in distances:
                distances[target] = distances[source] + 1
                queue.append(target)

    result = {node: hops for node, hops in distances.items() if node != 'ROOT_42'}
    cycles = [distances[source] + 1 for source, target in final_edges
              if target == 'ROOT_42' and source in distances]
    if cycles:
        result['ROOT_42'] = min(cycles)
    return result


def test_99_execute_script_on_unpredictable_fixture():
    token = secrets.token_hex(8)
    a, b, c, d, e, x, y = [f'{token}_{name}' for name in 'abcdefg']

    initial_edges = [
        ('ROOT_42', a, 1.0, 100),
        ('ROOT_42', a, 9.0, 50),
        ('ROOT_42', b, 2.0, 120),
        (a, c, 3.0, 130),
        (a, c, 8.0, 60),
        (b, c, 4.0, 140),
        (c, d, 5.0, 150),
        (d, a, 6.0, 160),
        (x, y, 7.0, 170),
    ]
    csv_edges = [
        ('ROOT_42', b, 12.5, 220),
        (a, c, 99.0, 90),
        (d, e, 13.5, 300),
        (e, 'ROOT_42', 14.5, 310),
    ]

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT, properties_json TEXT)')
    conn.execute('CREATE TABLE edges (source TEXT, target TEXT, weight REAL, updated_at INTEGER)')
    node_ids = ['ROOT_42', a, b, c, d, e, x, y]
    conn.executemany('INSERT INTO nodes VALUES (?, ?, ?)', [(n, 'concept', '{}') for n in node_ids])
    conn.executemany('INSERT INTO edges VALUES (?, ?, ?, ?)', initial_edges)
    conn.commit()
    conn.close()

    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['source', 'target', 'weight', 'updated_at'])
        writer.writerows(csv_edges)

    expected_edges = {}
    for source, target, weight, updated_at in initial_edges:
        key = (source, target)
        if key not in expected_edges or updated_at > expected_edges[key][1]:
            expected_edges[key] = (weight, updated_at)
    for source, target, weight, updated_at in csv_edges:
        key = (source, target)
        if key not in expected_edges or updated_at > expected_edges[key][1]:
            expected_edges[key] = (weight, updated_at)
    expected_json = derived_hops(expected_edges)

    launcher_path = f'/tmp/process_graph_launcher_{token}.py'
    trace_path = f'/tmp/process_graph_trace_{token}.json'
    make_launcher(launcher_path)
    try:
        result = subprocess.run(
            [sys.executable, launcher_path, SCRIPT_PATH, trace_path],
            cwd='/home/user', text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, \
            f"process_graph.py failed on a fresh fixture:\n{result.stdout}\n{result.stderr}"

        with open(trace_path) as f:
            events = json.load(f)
    finally:
        for path in (launcher_path, trace_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    recursive_queries = [event for event in events
                         if re.search(r'\bWITH\s+RECURSIVE\b', event['sql'], re.I)]
    assert recursive_queries, "process_graph.py did not execute a recursive CTE."

    parameterized_inserts = []
    for event in events:
        sql = event['sql']
        has_placeholder = '?' in sql or re.search(r'[:@$][A-Za-z_]\w*', sql)
        if event['parameterized'] and has_placeholder and re.search(r'\bINSERT\b', sql, re.I):
            parameterized_inserts.append(event)
    assert parameterized_inserts, \
        "CSV edge insertion/upsert was not executed using a parameterized INSERT query."

    conn = sqlite3.connect(DB_PATH)
    try:
        assert_unique_index(conn)
        duplicates = conn.execute(
            'SELECT source, target, COUNT(*) FROM edges '
            'GROUP BY source, target HAVING COUNT(*) > 1'
        ).fetchall()
        assert duplicates == [], "Stale duplicate rows remain in the dynamic fixture."

        actual_rows = conn.execute(
            'SELECT source, target, weight, updated_at FROM edges'
        ).fetchall()
        actual_edges = {(s, t): (w, ts) for s, t, w, ts in actual_rows}
        assert actual_edges == expected_edges, \
            "The cleaned/upserted edges do not match values derived from the dynamic input."
    finally:
        conn.close()

    assert os.path.isfile(JSON_PATH), f"JSON output file missing at {JSON_PATH}"
    with open(JSON_PATH) as f:
        output = json.load(f)
    assert isinstance(output, dict), "JSON root should be a dictionary."
    assert output == expected_json, \
        "Traversal output does not match minimum hop counts derived from the dynamic graph."
    assert all(type(value) is int for value in output.values()), \
        "All JSON hop counts must be integers."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
