#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

import pytest

DB_PATH = '/home/user/graph.db'
JSON_PATH = '/home/user/subgraph.json'
SCRIPT_PATH = '/home/user/etl_graph.py'
ORIGINAL_TRACE = []

RUNNER = r'''
import json
import runpy
import sqlite3
import sys

script_path, trace_path = sys.argv[1], sys.argv[2]
statements = []
original_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    conn = original_connect(*args, **kwargs)
    conn.set_trace_callback(statements.append)
    return conn

sqlite3.connect = traced_connect
try:
    runpy.run_path(script_path, run_name='__main__')
finally:
    with open(trace_path, 'w', encoding='utf-8') as f:
        json.dump(statements, f)
'''


def run_script():
    fd, trace_path = tempfile.mkstemp(prefix='etl-trace-', suffix='.json')
    os.close(fd)
    try:
        result = subprocess.run(
            [sys.executable, '-c', RUNNER, SCRIPT_PATH, trace_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'etl_graph.py exited with status {result.returncode}. '
            f'stdout: {result.stdout}\nstderr: {result.stderr}'
        )
        with open(trace_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    finally:
        if os.path.exists(trace_path):
            os.remove(trace_path)


def assert_required_sql_was_executed(statements):
    recursive = [s for s in statements if re.search(r'\bWITH\s+RECURSIVE\b', s, re.I)]
    assert len(recursive) == 1, (
        'The script must execute one SQL traversal query using WITH RECURSIVE; '
        f'observed {len(recursive)} recursive statements.'
    )

    traversal = recursive[0]
    assert re.search(r'\bedges\b', traversal, re.I), 'The recursive query must traverse edges.'
    assert re.search(r'\bnodes\b', traversal, re.I), 'The recursive query must join nodes in the same query.'
    assert re.search(r'\bdepth\b', traversal, re.I), 'The recursive query must track traversal depth.'
    assert re.search(r'\bsource_id\b', traversal, re.I)
    assert re.search(r'\btarget_id\b', traversal, re.I)

    non_recursive_edge_reads = []
    for statement in statements:
        if statement == traversal:
            continue
        if re.search(r'\bedges\b', statement, re.I) and re.search(r'\b(SELECT|WITH)\b', statement, re.I):
            non_recursive_edge_reads.append(statement)
    assert not non_recursive_edge_reads, (
        'Traversal data must be retrieved by the single recursive query, not by separate edge queries.'
    )

    creates = [
        s for s in statements
        if re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', s, re.I)
        and re.search(r'\bidx_edges_source\b', s, re.I)
        and re.search(r'\bedges\b', s, re.I)
    ]
    assert creates, "etl_graph.py did not execute CREATE INDEX for 'idx_edges_source'."


def load_json():
    assert os.path.exists(JSON_PATH), f'Exported JSON file {JSON_PATH} is missing.'
    try:
        with open(JSON_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f'Failed to parse JSON from {JSON_PATH}: {e}')
    except Exception as e:
        pytest.fail(f'Error reading {JSON_PATH}: {e}')


def validate_shape(data):
    assert isinstance(data, list), 'JSON root must be an array.'
    required = {'source_id', 'target_id', 'target_name', 'target_category', 'depth'}
    for i, row in enumerate(data):
        assert isinstance(row, dict), f'Item {i} must be an object.'
        assert set(row) == required, f'Item {i} has incorrect keys: {set(row)}.'
        assert type(row['source_id']) is int
        assert type(row['target_id']) is int
        assert type(row['depth']) is int
        assert isinstance(row['target_name'], str)
        assert isinstance(row['target_category'], str)


def expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        nodes = {
            row[0]: (row[1], row[2])
            for row in conn.execute('SELECT id, name, category FROM nodes')
        }
        edges = list(conn.execute('SELECT source_id, target_id FROM edges'))
    finally:
        conn.close()

    outgoing = {}
    for source_id, target_id in edges:
        outgoing.setdefault(source_id, []).append(target_id)

    result = []
    frontier = [42]
    for depth in range(1, 4):
        next_frontier = []
        for source_id in frontier:
            for target_id in outgoing.get(source_id, []):
                next_frontier.append(target_id)
                if target_id in nodes:
                    name, category = nodes[target_id]
                    result.append({
                        'source_id': source_id,
                        'target_id': target_id,
                        'target_name': name,
                        'target_category': category,
                        'depth': depth,
                    })
        frontier = next_frontier
    result.sort(key=lambda row: (row['depth'], row['target_id']))
    return result


def setup_module(module):
    assert os.path.isfile(SCRIPT_PATH), f'Required Python script {SCRIPT_PATH} is missing.'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f'{SCRIPT_PATH} must be a regular file.'
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} is missing.'

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('DROP INDEX IF EXISTS idx_edges_source')
        conn.commit()
    finally:
        conn.close()
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    global ORIGINAL_TRACE
    ORIGINAL_TRACE = run_script()


def test_script_executes_required_sql():
    assert_required_sql_was_executed(ORIGINAL_TRACE)


def test_index_exists():
    """Check if the index idx_edges_source was created on the edges table."""
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} is missing.'

    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_source'")
        index_row = c.fetchone()
        assert index_row is not None, "Index 'idx_edges_source' is missing in the database."
        columns = [row[2] for row in c.execute("PRAGMA index_info('idx_edges_source')")]
        assert columns == ['source_id'], (
            "Index 'idx_edges_source' must index edges.source_id to optimize outgoing-edge lookup."
        )
    except sqlite3.Error as e:
        pytest.fail(f'SQLite error occurred: {e}')
    finally:
        if 'conn' in locals():
            conn.close()


def test_json_exists_and_content():
    """Check if the exported JSON file exists and contains the correct traversal results."""
    data = load_json()

    expected_data = [
        {'source_id': 42, 'target_id': 101, 'target_name': 'child1', 'target_category': 'sub', 'depth': 1},
        {'source_id': 42, 'target_id': 102, 'target_name': 'child2', 'target_category': 'sub', 'depth': 1},
        {'source_id': 101, 'target_id': 201, 'target_name': 'grandchild1', 'target_category': 'leaf', 'depth': 2},
        {'source_id': 102, 'target_id': 202, 'target_name': 'grandchild2', 'target_category': 'leaf', 'depth': 2},
        {'source_id': 202, 'target_id': 301, 'target_name': 'greatgrandchild1', 'target_category': 'leaf', 'depth': 3},
    ]

    assert isinstance(data, list), 'JSON root must be an array.'
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} items, got {len(data)}.'
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f'Mismatch at index {i}. Expected {expected}, got {actual}.'
    validate_shape(data)


def test_script_handles_changed_graph_via_recursive_query():
    backup_fd, backup_path = tempfile.mkstemp(prefix='graph-backup-', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.executescript('''
                DROP TABLE IF EXISTS edges;
                DROP TABLE IF EXISTS nodes;
                CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, category TEXT);
                CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight REAL);
            ''')
            conn.executemany('INSERT INTO nodes VALUES (?, ?, ?)', [
                (42, 'changed_root', 'origin'),
                (710, 'alpha', 'service'),
                (720, 'beta', 'service'),
                (730, 'gamma', 'library'),
                (740, 'delta', 'library'),
                (750, 'epsilon', 'endpoint'),
                (760, 'depth_four', 'excluded'),
                (900, 'disconnected', 'none'),
            ])
            conn.executemany('INSERT INTO edges VALUES (?, ?, ?)', [
                (42, 710, 0.1),
                (42, 720, 0.2),
                (710, 730, 0.3),
                (720, 740, 0.4),
                (740, 750, 0.5),
                (750, 760, 0.6),
                (900, 710, 0.7),
            ])
            conn.commit()
        finally:
            conn.close()

        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        trace = run_script()
        assert_required_sql_was_executed(trace)

        actual = load_json()
        validate_shape(actual)
        expected = expected_from_database()
        assert actual == expected, f'Changed-graph traversal mismatch. Expected {expected}, got {actual}.'
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
