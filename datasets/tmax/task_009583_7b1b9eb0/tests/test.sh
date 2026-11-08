#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import json
import os
import random
import re
import sqlite3
import subprocess
import sys
import tempfile
import pytest

DB_PATH = '/home/user/graph.db'
SCRIPT_PATH = '/home/user/analyze.py'
JSON_PATH = '/home/user/top_nodes.json'


def canonical_rows():
    types = ['A', 'B', 'C', 'D']
    nodes = [(i, types[i % 4]) for i in range(1, 101)]
    rng = random.Random(42)
    edges = []
    for _ in range(300):
        src = rng.randint(1, 100)
        dst = rng.randint(1, 100)
        if src != dst:
            edges.append((src, dst))
    return nodes, edges


def validate_canonical_database():
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        objects = conn.execute(
            "SELECT type, name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [('table', 'edges'), ('table', 'nodes')], (
            f"Unexpected database objects: {objects}"
        )

        nodes_info = conn.execute('PRAGMA table_info(nodes)').fetchall()
        edges_info = conn.execute('PRAGMA table_info(edges)').fetchall()
        assert [(r[1], r[2], r[5]) for r in nodes_info] == [
            ('id', 'INTEGER', 1), ('type', 'TEXT', 0)
        ], "The nodes table schema was modified"
        assert [(r[1], r[2], r[5]) for r in edges_info] == [
            ('src', 'INTEGER', 0), ('dst', 'INTEGER', 0)
        ], "The edges table schema was modified"

        expected_nodes, expected_edges = canonical_rows()
        actual_nodes = conn.execute('SELECT id, type FROM nodes ORDER BY id').fetchall()
        actual_edges = conn.execute('SELECT src, dst FROM edges').fetchall()
        assert actual_nodes == expected_nodes, "The original nodes data was modified"
        assert collections.Counter(actual_edges) == collections.Counter(expected_edges), (
            "The original edges data was modified"
        )
    finally:
        conn.close()


def expected_for_rows(nodes, edges):
    conn = sqlite3.connect(':memory:')
    conn.row_factory = sqlite3.Row
    try:
        conn.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT)')
        conn.execute('CREATE TABLE edges (src INTEGER, dst INTEGER)')
        conn.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
        conn.executemany('INSERT INTO edges VALUES (?, ?)', edges)
        query = """
        WITH TwoHop AS (
            SELECT n.type, n.id as src_id, n2.id as dst_id
            FROM nodes n
            JOIN edges e1 ON n.id = e1.src
            JOIN edges e2 ON e1.dst = e2.src
            JOIN nodes n2 ON e2.dst = n2.id
        ),
        Aggregated AS (
            SELECT type, src_id as id, COUNT(DISTINCT dst_id) as ext_degree
            FROM TwoHop
            GROUP BY type, src_id
        )
        SELECT type, id, ext_degree,
               RANK() OVER(PARTITION BY type ORDER BY ext_degree DESC, id ASC) as rnk
        FROM Aggregated
        """
        rows = [dict(row) for row in conn.execute(query).fetchall()]
    finally:
        conn.close()

    expected = []
    for row in rows:
        if row['rnk'] == 1:
            expected.append({
                'type': row['type'],
                'id': row['id'],
                'ext_degree': row['ext_degree'],
            })
    return sorted(expected, key=lambda x: (x['type'], x['id']))


def get_expected_top_nodes():
    nodes, edges = canonical_rows()
    return expected_for_rows(nodes, edges)


def load_and_validate_output(expected):
    assert os.path.isfile(JSON_PATH), f"Output file missing: {JSON_PATH}"
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(data, list), f"JSON root must be an array, got {type(data).__name__}"
    for item in data:
        assert isinstance(item, dict), "Each item in the JSON array must be an object."
        assert set(item.keys()) == {'type', 'id', 'ext_degree'}, (
            "Object keys must be exactly 'type', 'id', 'ext_degree'. "
            f"Found: {list(item.keys())}"
        )

    actual = sorted(data, key=lambda x: (x.get('type', ''), x.get('id', 0)))
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} top nodes, but found {len(actual)}."
    )
    for actual_item, expected_item in zip(actual, expected):
        assert actual_item == expected_item, (
            f"Mismatch in top nodes. Expected: {expected_item}, Actual: {actual_item}"
        )


def run_script():
    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def install_database(nodes, edges):
    for suffix in ('', '-wal', '-shm', '-journal'):
        path = DB_PATH + suffix
        if os.path.lexists(path):
            os.remove(path)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT)')
        conn.execute('CREATE TABLE edges (src INTEGER, dst INTEGER)')
        conn.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
        conn.executemany('INSERT INTO edges VALUES (?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


def assert_required_sql_is_present():
    assert os.path.isfile(SCRIPT_PATH), f"Analysis script missing: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"Analysis script is not valid Python: {exc}")

    strings = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    candidates = []
    for value in strings:
        sql = re.sub(r'\s+', ' ', value.lower()).strip()
        checks = [
            r'join\s+edges\s+e1\s+on\s+n\.id\s*=\s*e1\.src',
            r'join\s+edges\s+e2\s+on\s+e1\.dst\s*=\s*e2\.src',
            r'join\s+nodes\s+n2\s+on\s+e2\.dst\s*=\s*n2\.id',
            r'count\s*\(\s*distinct\s+dst_id\s*\)',
            r'rank\s*\(\s*\)\s*over\s*\(\s*partition\s+by\s+type\s+order\s+by\s+ext_degree\s+desc\s*,\s*id\s+asc\s*\)',
        ]
        if all(re.search(pattern, sql) for pattern in checks):
            candidates.append(sql)

    assert candidates, (
        "analyze.py must contain the corrected two-hop SQL joins, distinct "
        "destination count, and required window ranking"
    )
    assert all('n.type = n2.type' not in sql for sql in candidates), (
        "The buggy node-type join is still present in the analysis query"
    )


def test_analyze_sql_and_execution_on_independent_input():
    validate_canonical_database()
    assert_required_sql_is_present()

    rng = random.SystemRandom()
    probe_nodes = [(i, ['probe-A', 'probe-B', 'probe-C'][i % 3]) for i in range(1, 37)]
    probe_edges = []
    for _ in range(180):
        src = rng.randint(1, 36)
        dst = rng.randint(1, 36)
        if src != dst:
            probe_edges.append((src, dst))
    probe_expected = expected_for_rows(probe_nodes, probe_edges)

    fd, backup_path = tempfile.mkstemp(prefix='graph-original-', suffix='.db')
    os.close(fd)
    os.remove(backup_path)
    os.replace(DB_PATH, backup_path)
    try:
        install_database(probe_nodes, probe_edges)
        run_script()
        load_and_validate_output(probe_expected)
    finally:
        for suffix in ('', '-wal', '-shm', '-journal'):
            path = DB_PATH + suffix
            if os.path.lexists(path):
                os.remove(path)
        os.replace(backup_path, DB_PATH)

    run_script()
    validate_canonical_database()


def test_top_nodes_json_exists_and_valid():
    assert os.path.isfile(JSON_PATH), f"Output file missing: {JSON_PATH}"
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")
    assert isinstance(data, list), f"JSON root must be an array, got {type(data).__name__}"


def test_top_nodes_json_correctness():
    if not os.path.isfile(JSON_PATH):
        pytest.skip("Output file missing")

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Output file is not valid JSON")

    expected = get_expected_top_nodes()

    for item in data:
        assert isinstance(item, dict), "Each item in the JSON array must be an object."
        assert set(item.keys()) == {'type', 'id', 'ext_degree'}, (
            "Object keys must be exactly 'type', 'id', 'ext_degree'. "
            f"Found: {list(item.keys())}"
        )

    data_sorted = sorted(data, key=lambda x: (x.get('type', ''), x.get('id', 0)))
    assert len(data_sorted) == len(expected), (
        f"Expected {len(expected)} top nodes, but found {len(data_sorted)}."
    )

    for actual_item, expected_item in zip(data_sorted, expected):
        assert actual_item == expected_item, (
            f"Mismatch in top nodes. Expected: {expected_item}, Actual: {actual_item}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
