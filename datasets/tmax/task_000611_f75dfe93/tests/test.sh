#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/graph.db'
SCRIPT_PATH = '/home/user/analyze_graph.py'
RESULT_PATH = '/home/user/result.json'


def original_edges():
    random.seed(42)
    edges = set()
    for _ in range(2000):
        u = random.randint(1, 50)
        v = random.randint(1, 50)
        if u != v:
            edges.add((u, v))
    return edges


def assert_original_graph_unchanged():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        columns = conn.execute("PRAGMA table_info(edges)").fetchall()
        assert [row[1] for row in columns] == ['source', 'target'], "The edges table schema was modified."
        rows = conn.execute("SELECT source, target FROM edges").fetchall()
        assert len(rows) == len(set(rows)), "Duplicate or additional graph edges were introduced."
        assert set(rows) == original_edges(), "The graph data was modified."
    finally:
        conn.close()


def triangle_count(edges):
    return sum(
        1
        for a, b in edges
        for b2, c in edges
        for c2, a2 in edges
        if b == b2 and c == c2 and a == a2
    )


def invoke_count_function(timeout=15):
    wrapper = r'''
import importlib.util
spec = importlib.util.spec_from_file_location("submitted_analyze_graph", "/home/user/analyze_graph.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not hasattr(module, "count_triangles") or not callable(module.count_triangles):
    raise AssertionError("analyze_graph.py must define callable count_triangles()")
value = module.count_triangles()
print("__VERIFIER_RETURN__=" + repr(value))
'''
    proc = subprocess.run(
        ['python3', '-c', wrapper], text=True, capture_output=True, timeout=timeout
    )
    assert proc.returncode == 0, (
        "Calling count_triangles() failed.\nSTDOUT:\n"
        + proc.stdout + "\nSTDERR:\n" + proc.stderr
    )
    markers = [line for line in proc.stdout.splitlines() if line.startswith('__VERIFIER_RETURN__=')]
    assert markers, "count_triangles() did not return a verifiable value."
    value = ast.literal_eval(markers[-1].split('=', 1)[1])
    assert isinstance(value, int) and not isinstance(value, bool), "count_triangles() must return an integer."
    return value


def test_graph_was_not_mutated():
    assert_original_graph_unchanged()


def test_database_index_created():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Keep the original assertion: at least one user-created index must exist.
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'")
    indexes = cursor.fetchall()
    user_indexes = [idx[0] for idx in indexes if idx[0] and not idx[0].startswith('sqlite_')]
    assert len(user_indexes) >= 1, "No user-created index found on 'edges' table to optimize the query."

    # At least one index must actually index a join/closure column rather than an expression or constant.
    useful = False
    for name in user_indexes:
        info = cursor.execute(f"PRAGMA index_info({json.dumps(name)})").fetchall()
        indexed_columns = [row[2] for row in info]
        if indexed_columns and indexed_columns[0] in ('source', 'target'):
            useful = True
    assert useful, "No index on an edges join column was created to optimize the triangle query."
    conn.close()


def test_analyze_graph_is_fixed_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.getsize(SCRIPT_PATH) > 0, "analyze_graph.py is empty."

    # Execute the submitted artifact normally against the real database.
    proc = subprocess.run(['python3', SCRIPT_PATH], text=True, capture_output=True, timeout=30)
    assert proc.returncode == 0, (
        "Executing analyze_graph.py failed.\nSTDOUT:\n"
        + proc.stdout + "\nSTDERR:\n" + proc.stderr
    )
    assert_original_graph_unchanged()

    # Exercise count_triangles() on verifier-generated graphs. The expected answers
    # are derived independently, so merely writing the known result.json cannot pass.
    cases = [
        [(1, 2), (2, 3), (3, 1), (1, 4), (4, 5)],
        [(1, 2), (2, 1), (2, 3), (3, 4), (4, 2), (7, 8)],
        [(1, 2), (1, 2), (2, 3), (3, 1), (3, 4), (4, 1)],
    ]
    rng = random.SystemRandom()
    nodes = list(range(10, 18))
    random_case = []
    for a in nodes:
        for b in nodes:
            if a != b and rng.randrange(100) < 32:
                random_case.append((a, b))
    x, y, z = rng.sample(nodes, 3)
    random_case.extend([(x, y), (y, z), (z, x)])
    cases.append(random_case)

    backup_dir = tempfile.mkdtemp(prefix='graph-verifier-')
    saved = []
    try:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                destination = os.path.join(backup_dir, 'graph.db' + suffix)
                os.replace(path, destination)
                saved.append((destination, path))

        for edges in cases:
            for suffix in ('', '-wal', '-shm'):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)
            conn = sqlite3.connect(DB_PATH)
            conn.execute('CREATE TABLE edges (source INTEGER, target INTEGER)')
            conn.executemany('INSERT INTO edges VALUES (?, ?)', edges)
            conn.commit()
            conn.close()

            actual = invoke_count_function()
            expected = triangle_count(edges)
            assert actual == expected, f"count_triangles() returned {actual}; expected {expected} on a verifier-generated graph."
    finally:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        for source, destination in saved:
            os.replace(source, destination)
        shutil.rmtree(backup_dir, ignore_errors=True)

    assert_original_graph_unchanged()


def test_result_json_valid_and_correct():
    assert os.path.isfile(RESULT_PATH), f"Result file missing at {RESULT_PATH}"

    with open(RESULT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {RESULT_PATH} is not valid JSON.")

    assert isinstance(data, dict), "result.json must contain a JSON object."
    assert set(data) == {'triangle_count', 'index_statements'}, "result.json does not strictly match the required schema."
    assert "triangle_count" in data, "Key 'triangle_count' missing in result.json"
    assert "index_statements" in data, "Key 'index_statements' missing in result.json"
    assert isinstance(data['triangle_count'], int) and not isinstance(data['triangle_count'], bool), "'triangle_count' must be an integer."

    # Keep the original corrected natural-join recomputation.
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = '''
        SELECT COUNT(*)
        FROM edges e1
        JOIN edges e2 ON e1.target = e2.source
        JOIN edges e3 ON e2.target = e3.source AND e3.target = e1.source
    '''
    cursor.execute(query)
    expected_count = cursor.fetchone()[0]

    assert data["triangle_count"] == expected_count, f"Incorrect triangle_count. Expected {expected_count}, got {data['triangle_count']}."

    index_statements = data["index_statements"]
    assert isinstance(index_statements, list), "'index_statements' must be a list of strings."
    assert len(index_statements) >= 1, "'index_statements' list is empty. It should contain the CREATE INDEX statement(s)."

    actual_indexes = {
        row[0]: row[1]
        for row in cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='edges'")
        if row[0] and not row[0].startswith('sqlite_')
    }

    listed_real_index = False
    for stmt in index_statements:
        assert isinstance(stmt, str), "All items in 'index_statements' must be strings."
        assert "CREATE INDEX" in stmt.upper(), f"Statement '{stmt}' does not look like a CREATE INDEX statement."

        # Execute each claimed statement on a clean schema to establish its real
        # index name/table/columns, then require that same index in graph.db.
        probe = sqlite3.connect(':memory:')
        probe.execute('CREATE TABLE edges (source INTEGER, target INTEGER)')
        try:
            probe.execute(stmt)
        except sqlite3.Error as exc:
            pytest.fail(f"Invalid index statement '{stmt}': {exc}")
        created = probe.execute(
            "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        assert len(created) == 1, f"Statement '{stmt}' must create exactly one index."
        name, table = created[0]
        assert table == 'edges', f"Statement '{stmt}' does not create an index on edges."
        assert name in actual_indexes, f"Index '{name}' listed in result.json does not exist in graph.db."
        probe_columns = [row[2] for row in probe.execute(f"PRAGMA index_info({json.dumps(name)})")]
        actual_columns = [row[2] for row in cursor.execute(f"PRAGMA index_info({json.dumps(name)})")]
        assert probe_columns == actual_columns, f"Listed statement for index '{name}' does not match the index in graph.db."
        if actual_columns and actual_columns[0] in ('source', 'target'):
            listed_real_index = True
        probe.close()

    assert listed_real_index, "index_statements does not identify a useful index actually present in graph.db."
    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
