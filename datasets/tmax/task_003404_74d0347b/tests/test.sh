#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
from pathlib import Path

import pytest

PIPELINE = Path('/home/user/etl/pipeline')
CARGO_TOML = PIPELINE / 'Cargo.toml'
OUTPUT = Path('/home/user/etl/shortest_path.json')
DATABASE = Path('/home/user/etl/supply_chain.db')


def test_rust_project_exists():
    """Verify that the Rust project was created with Cargo."""
    assert CARGO_TOML.exists(), f"Rust project not found. Expected Cargo.toml at {CARGO_TOML}"
    assert CARGO_TOML.is_file(), f"Path {CARGO_TOML} is not a file."

    rust_sources = [p for p in (PIPELINE / 'src').rglob('*.rs') if p.is_file()]
    assert rust_sources, f"No Rust source files found under {PIPELINE / 'src'}."
    assert any(p.stat().st_size > 0 for p in rust_sources), "Rust source files are empty."


def test_output_file_exists():
    """Verify that the output JSON file exists."""
    assert OUTPUT.exists(), f"Output file {OUTPUT} does not exist."
    assert OUTPUT.is_file(), f"Path {OUTPUT} is not a file."


def test_shortest_path_result():
    """Preserve the original database result assertion."""
    try:
        with OUTPUT.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT} does not contain valid JSON.")

    expected_path = ["Product_Omega", "Subassembly_B", "Component_Y", "Raw_Silicon"]
    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert data == expected_path, f"Incorrect shortest path. Expected {expected_path}, but got {data}."


def shortest_path(nodes, edges):
    names = {node_id: name for node_id, name, _ in nodes}
    raw = {node_id for node_id, _, is_raw in nodes if is_raw == 1}
    start = next(node_id for node_id, name, _ in nodes if name == 'Product_Omega')
    graph = {}
    for parent, child, weight in edges:
        graph.setdefault(parent, []).append((child, weight))

    queue = [(0, start, [start])]
    best = {start: 0}
    while queue:
        distance, current, path = heapq.heappop(queue)
        if distance != best.get(current):
            continue
        if current in raw:
            return [names[node_id] for node_id in path]
        for child, weight in graph.get(current, []):
            candidate = distance + weight
            if candidate < best.get(child, float('inf')):
                best[child] = candidate
                heapq.heappush(queue, (candidate, child, path + [child]))
    raise AssertionError('Generated test graph has no path to a raw material.')


def test_build_run_reindex_and_dynamic_shortest_path():
    rust_sources = [p for p in (PIPELINE / 'src').rglob('*.rs') if p.is_file()]
    source = '\n'.join(p.read_text(errors='ignore') for p in rust_sources)
    source_without_comments = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    source_without_comments = re.sub(r'(?m)//.*$', '', source_without_comments)

    uses_reindex = re.search(r'\bREINDEX\b', source_without_comments, re.I) is not None
    bypasses_indexes = re.search(r'\bNOT\s+INDEXED\b', source_without_comments, re.I) is not None
    drops_indexes = re.search(r'\bDROP\s+INDEX\b', source_without_comments, re.I) is not None
    assert uses_reindex or bypasses_indexes or drops_indexes, (
        'Rust source must fix or bypass the corrupt edges indexes, for example by executing '
        'REINDEX; or querying edges with NOT INDEXED.'
    )

    nonce = secrets.token_hex(6)
    labels = {
        'omega': 'Product_Omega',
        'a': f'Assembly_A_{nonce}',
        'b': f'Assembly_B_{nonce}',
        'c': f'Component_C_{nonce}',
        'r1': f'Raw_One_{nonce}',
        'r2': f'Raw_Two_{nonce}',
        'decoy': f'Decoy_{nonce}',
    }
    shuffled_ids = random.sample(range(101, 5000), len(labels))
    ids = dict(zip(labels, shuffled_ids))
    nodes = [
        (ids['omega'], labels['omega'], 0),
        (ids['a'], labels['a'], 0),
        (ids['b'], labels['b'], 0),
        (ids['c'], labels['c'], 0),
        (ids['r1'], labels['r1'], 1),
        (ids['r2'], labels['r2'], 1),
        (ids['decoy'], labels['decoy'], 0),
    ]
    edges = [
        (ids['omega'], ids['a'], random.randint(20, 24)),
        (ids['a'], ids['r1'], random.randint(10, 14)),
        (ids['omega'], ids['b'], random.randint(2, 4)),
        (ids['b'], ids['c'], random.randint(2, 4)),
        (ids['c'], ids['r2'], random.randint(2, 4)),
        (ids['b'], ids['r1'], random.randint(15, 18)),
        (ids['omega'], ids['r2'], random.randint(25, 29)),
        (ids['a'], ids['c'], random.randint(20, 24)),
        (ids['c'], ids['b'], 1),
        (ids['decoy'], ids['r1'], 1),
    ]
    expected = shortest_path(nodes, edges)

    if DATABASE.exists():
        DATABASE.unlink()
    creator = sqlite3.connect(DATABASE)
    creator.executescript('''
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, is_raw INTEGER);
        CREATE TABLE edges (parent_id INTEGER, child_id INTEGER, lead_time_days INTEGER);
    ''')
    creator.executemany('INSERT INTO nodes VALUES (?, ?, ?)', nodes)
    creator.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
    creator.executescript('''
        CREATE INDEX idx_parent ON edges(parent_id);
        CREATE INDEX idx_child ON edges(child_id);
    ''')
    creator.commit()
    creator.close()

    observer = sqlite3.connect(DATABASE)
    version_before = observer.execute('PRAGMA data_version').fetchone()[0]
    if OUTPUT.exists():
        OUTPUT.unlink()

    try:
        result = subprocess.run(
            ['cargo', 'run', '--quiet', '--manifest-path', str(CARGO_TOML)],
            cwd=PIPELINE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        version_after = observer.execute('PRAGMA data_version').fetchone()[0]
        integrity = observer.execute('PRAGMA integrity_check').fetchone()[0]
    finally:
        observer.close()

    assert result.returncode == 0, (
        f'Cargo failed to build or run the Rust project (exit {result.returncode}).\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert integrity == 'ok', f'Program left the SQLite database invalid: {integrity}'
    if (uses_reindex or drops_indexes) and not bypasses_indexes:
        assert version_after != version_before, (
            'The program claims to rebuild/drop indexes, but running it did not modify the database.'
        )

    assert OUTPUT.exists(), 'Running the Rust project did not recreate shortest_path.json.'
    assert OUTPUT.is_file(), f'Path {OUTPUT} is not a file.'
    try:
        with OUTPUT.open('r') as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Generated output is not valid JSON: {exc}')

    assert isinstance(actual, list), f'Expected JSON root to be a list, got {type(actual).__name__}.'
    assert all(isinstance(item, str) for item in actual), 'Output must be an array containing only strings.'
    assert actual == expected, f'Expected dynamically computed shortest path {expected}, got {actual}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
