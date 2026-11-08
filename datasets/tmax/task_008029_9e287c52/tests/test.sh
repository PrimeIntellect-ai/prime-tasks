#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import sqlite3
import subprocess

import pytest

SOURCE = '/home/user/solve.cpp'
BINARY = '/home/user/solve'
DB = '/home/user/graph.db'
OUTPUT = '/home/user/reachable.json'


def run_program():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=15)
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{OUTPUT} does not exist after executing the program."


def read_output():
    with open(OUTPUT, 'r') as f:
        raw = f.read()
    assert re.fullmatch(r'\s*\[(?:\s*-?\d+\s*(?:,\s*-?\d+\s*)*)?\]\s*', raw), (
        "reachable.json must contain only one JSON array of integers."
    )
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"{OUTPUT} does not contain valid JSON.")
    assert isinstance(data, list), "The JSON output must be a list."
    assert all(type(value) is int for value in data), "Every array element must be an integer."
    assert data == sorted(set(data)), "Reachable node IDs must be distinct and sorted ascending."
    return data


def assert_covering_index():
    assert os.path.isfile(DB), f"{DB} is missing."
    conn = sqlite3.connect(DB)
    try:
        indexes = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges';"
        ).fetchall()
        assert len(indexes) > 0, "No index was created on the 'edges' table."
        covering = []
        for (name,) in indexes:
            columns = [row[0] for row in conn.execute(
                "SELECT name FROM pragma_index_info(?) ORDER BY seqno", (name,)
            )]
            if columns == ['source', 'target']:
                covering.append(name)
        assert covering, (
            "The edges table must have a covering index whose ordered columns are "
            "exactly (source, target)."
        )
    finally:
        conn.close()


def expected_reachable(edges, start=42, max_depth=3):
    reached = {start}
    frontier = {start}
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, set()).add(target)
    for _ in range(max_depth):
        next_frontier = set()
        for source in frontier:
            next_frontier.update(adjacency.get(source, ()))
        reached.update(next_frontier)
        frontier = next_frontier
    return sorted(reached)


@pytest.fixture(scope='session', autouse=True)
def compile_and_execute_submission():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    with open(SOURCE, 'r', errors='replace') as f:
        source = f.read()

    uncommented = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    uncommented = re.sub(r'//[^\n]*', '', uncommented)
    assert re.search(r'#\s*include\s*[<\"]sqlite3\.h[>\"]', uncommented), (
        "solve.cpp must include <sqlite3.h>."
    )
    assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', uncommented), (
        "solve.cpp must connect through the SQLite3 C/C++ API."
    )
    assert re.search(r'\bsqlite3_(?:exec|prepare(?:16)?_v2)\s*\(', uncommented), (
        "solve.cpp must execute SQL through the SQLite3 C/C++ API."
    )
    assert re.search(r'\bWITH\s+RECURSIVE\b', uncommented, flags=re.I), (
        "solve.cpp must contain and execute a recursive CTE."
    )

    result = subprocess.run(
        ['g++', SOURCE, '-lsqlite3', '-o', BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"solve.cpp did not compile: {result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not produce an executable /home/user/solve."
    )
    run_program()


def test_reachable_json_exists():
    """Verify that the reachable.json file was created."""
    assert os.path.isfile(OUTPUT), f"{OUTPUT} does not exist."


def test_reachable_json_content():
    """Verify that the reachable.json file contains the correct reachable nodes."""
    data = read_output()
    expected = [42, 100, 101, 200, 201, 202, 300, 301]
    assert data == expected, (
        f"Expected {expected}, but got {data}. Check your recursive CTE and depth constraint."
    )


def test_edges_index_created():
    """Verify that the required covering index was created on the edges table."""
    assert_covering_index()


def test_program_on_unseen_graph():
    """Execute the submitted binary on a graph whose answer is generated at test time."""
    rng = random.SystemRandom()
    values = rng.sample(range(10000, 90000), 11)
    a, b, c, d, e, f, g, h, disconnected1, disconnected2, disconnected3 = values
    edges = [
        (42, a), (42, b),
        (a, c), (a, d), (b, e), (b, a),
        (c, f), (e, g), (d, 42),
        (f, h),
        (disconnected1, disconnected2), (disconnected2, disconnected3),
        (42, a),
    ]
    expected = expected_reachable(edges)

    for suffix in ('', '-wal', '-shm'):
        path = DB + suffix
        if os.path.exists(path):
            os.unlink(path)
    conn = sqlite3.connect(DB)
    try:
        conn.execute('CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT)')
        conn.execute('CREATE TABLE edges (source INTEGER, target INTEGER)')
        node_ids = {42}
        for source, target in edges:
            node_ids.add(source)
            node_ids.add(target)
        conn.executemany(
            'INSERT INTO nodes(id, label) VALUES (?, ?)',
            [(node_id, f'Node_{node_id}') for node_id in node_ids]
        )
        conn.executemany('INSERT INTO edges(source, target) VALUES (?, ?)', edges)
        conn.commit()
    finally:
        conn.close()

    run_program()
    actual = read_output()
    assert actual == expected, (
        f"On an unseen graph, expected {expected}, but the submitted program produced {actual}."
    )
    assert_covering_index()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
