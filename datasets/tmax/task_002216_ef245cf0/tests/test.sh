#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import re
import sqlite3
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/topology_recovery')
MANIFEST = PROJECT / 'Cargo.toml'
DB_PATH = Path('/home/user/network_backup.db')
OUTPUT_FILE = Path('/home/user/recovery_path.txt')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=180, **kwargs)


def executable_path():
    metadata = json.loads(run([
        'cargo', 'metadata', '--offline', '--no-deps',
        '--format-version', '1', '--manifest-path', str(MANIFEST)
    ], cwd=PROJECT).stdout)
    package = next((p for p in metadata['packages'] if Path(p['manifest_path']) == MANIFEST), None)
    assert package is not None, 'Could not identify the submitted Cargo package.'
    bins = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
    assert bins, 'The Rust project has no binary application target.'
    default_run = package.get('default_run')
    if default_run:
        selected = next((t for t in bins if t['name'] == default_run), None)
        assert selected is not None, 'Cargo default-run does not identify a binary target.'
    else:
        assert len(bins) == 1, 'The project must identify one runnable binary or set default-run.'
        selected = bins[0]
    filename = selected['name'] + ('.exe' if os.name == 'nt' else '')
    return Path(metadata['target_directory']) / 'debug' / filename


def create_database(nodes, edges):
    if DB_PATH.exists():
        DB_PATH.unlink()
    conn = sqlite3.connect(DB_PATH)
    conn.executescript('''
        CREATE TABLE topology_nodes (id TEXT PRIMARY KEY, region TEXT);
        CREATE TABLE topology_edges (source TEXT, target TEXT, cost INTEGER);
        CREATE INDEX idx_corrupted_source ON topology_edges(source);
    ''')
    conn.executemany('INSERT INTO topology_nodes (id, region) VALUES (?, ?)', nodes)
    conn.executemany('INSERT INTO topology_edges (source, target, cost) VALUES (?, ?, ?)', edges)
    conn.commit()
    conn.close()


def shortest_path(edges):
    graph = {}
    for source, target, cost in edges:
        graph.setdefault(source, []).append((target, cost))
    queue = [(0, 'NODE_START', ['NODE_START'])]
    best = {}
    while queue:
        cost, node, path = heapq.heappop(queue)
        if node in best and best[node] <= cost:
            continue
        best[node] = cost
        if node == 'NODE_END':
            return path, cost
        for target, edge_cost in graph.get(node, []):
            heapq.heappush(queue, (cost + edge_cost, target, path + [target]))
    raise AssertionError('Verifier graph has no route to NODE_END')


def run_submission():
    if OUTPUT_FILE.exists():
        OUTPUT_FILE.unlink()
    binary = executable_path()
    assert binary.is_file(), f'Compiled Rust executable missing: {binary}'
    run([str(binary)], cwd=PROJECT)
    assert OUTPUT_FILE.is_file(), 'The Rust application did not create recovery_path.txt.'


def assert_repaired_index():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_corrupted_source'")
    assert cur.fetchone() is None, "The corrupted index 'idx_corrupted_source' was not dropped."
    cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_covering'")
    assert cur.fetchone() is not None, "The new index 'idx_edges_covering' was not created."
    cur.execute("PRAGMA index_info('idx_edges_covering')")
    columns = [row[2] for row in cur.fetchall()]
    assert columns == ['source', 'target', 'cost'], (
        "Index 'idx_edges_covering' does not cover the correct columns in the correct order. "
        f"Expected ['source', 'target', 'cost'], found {columns}."
    )
    conn.close()


def test_00_rust_project_and_query_implementation():
    assert PROJECT.is_dir(), f'Rust project missing: {PROJECT}'
    assert MANIFEST.is_file(), f'Cargo manifest missing: {MANIFEST}'
    manifest = MANIFEST.read_text(errors='replace')
    assert re.search(r'(?im)^\s*rusqlite\s*=', manifest) or re.search(r'package\s*=\s*["\']rusqlite["\']', manifest), \
        'Cargo.toml must declare the rusqlite crate as a dependency.'

    rust_files = list(PROJECT.rglob('*.rs'))
    assert rust_files, 'No Rust source files were found in the project.'
    source = '\n'.join(p.read_text(errors='replace') for p in rust_files)
    assert re.search(r'\brusqlite\b', source), 'The Rust application does not use rusqlite.'
    assert re.search(
        r'select\b.{0,500}?from\s+topology_edges\b.{0,500}?where\s+[^;"\n]*source\s*=\s*(?:\?(?:\d+)?|[:@$][A-Za-z_]\w*)',
        source, re.IGNORECASE | re.DOTALL
    ), 'No parameterized outgoing-edge SQL query by source was found in the Rust code.'
    assert re.search(r'\b(?:params|named_params)\s*!|\.query(?:_map|_row)?\s*\(\s*(?:\[|\(|&)', source), \
        'The outgoing-edge query does not appear to bind a Rust value as a SQL parameter.'

    literals = re.findall(r'"(?:\\.|[^"\\])*"', source, re.DOTALL)
    literals += [m.group(2) for m in re.finditer(r'r(?P<h>#{0,8})"(.*?)"(?P=h)', source, re.DOTALL)]
    for literal in literals:
        if re.search(r'\bselect\b', literal, re.IGNORECASE) and re.search(r'\bfrom\s+topology_edges\b', literal, re.IGNORECASE):
            assert re.search(r'\bwhere\b', literal, re.IGNORECASE), \
                'Found a query that loads topology_edges without filtering outgoing neighbors.'

    run(['cargo', 'build', '--offline', '--manifest-path', str(MANIFEST)], cwd=PROJECT)
    assert executable_path().is_file(), 'Cargo did not produce the Rust application executable.'


def test_10_application_on_derived_graph():
    rng = random.SystemRandom()
    a, b, c = (rng.randint(2, 8) for _ in range(3))
    edges = [
        ('NODE_START', 'N_ALPHA', a),
        ('N_ALPHA', 'N_BETA', b),
        ('N_BETA', 'NODE_END', c),
        ('NODE_START', 'N_DECOY', a + b + c + rng.randint(8, 15)),
        ('N_DECOY', 'NODE_END', rng.randint(8, 15)),
        ('NODE_START', 'NODE_END', a + b + c + rng.randint(20, 30)),
        ('N_ALPHA', 'NODE_END', b + c + rng.randint(5, 12)),
        ('N_BETA', 'N_DECOY', rng.randint(20, 30)),
    ]
    nodes = [(n, 'test-region') for n in ['NODE_START', 'N_ALPHA', 'N_BETA', 'N_DECOY', 'NODE_END']]
    expected_path, expected_cost = shortest_path(edges)
    create_database(nodes, edges)
    run_submission()
    assert_repaired_index()
    expected = f"Path: {','.join(expected_path)} | Cost: {expected_cost}"
    actual = OUTPUT_FILE.read_text().strip()
    assert actual == expected, f'Derived-graph result was {actual!r}; expected {expected!r}.'


def test_20_run_application_on_original_database():
    nodes = [
        ('NODE_START', 'us-east'), ('N1', 'us-east'), ('N2', 'us-west'),
        ('N3', 'eu-central'), ('N4', 'ap-south'), ('NODE_END', 'eu-west')
    ]
    edges = [
        ('NODE_START', 'N1', 10), ('NODE_START', 'N2', 2), ('N1', 'N4', 5),
        ('N2', 'N3', 3), ('N3', 'NODE_END', 4), ('N1', 'NODE_END', 15),
        ('N4', 'NODE_END', 1), ('N2', 'NODE_END', 20)
    ]
    create_database(nodes, edges)
    run_submission()


def test_database_indices_repaired():
    """Verify that the corrupted index is dropped and the new covering index is created."""
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_corrupted_source'")
    assert cursor.fetchone() is None, "The corrupted index 'idx_corrupted_source' was not dropped."
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_covering'")
    assert cursor.fetchone() is not None, "The new index 'idx_edges_covering' was not created."
    cursor.execute("PRAGMA index_info('idx_edges_covering')")
    index_info = cursor.fetchall()
    columns = [row[2] for row in index_info]
    expected_columns = ['source', 'target', 'cost']
    assert columns == expected_columns, (
        f"Index 'idx_edges_covering' does not cover the correct columns in the correct order. "
        f"Expected {expected_columns}, found {columns}."
    )
    conn.close()


def test_recovery_path_file():
    """Verify that the recovery path file exists and contains the correct shortest path."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file missing: {OUTPUT_FILE}"
    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()
    expected_content = "Path: NODE_START,N2,N3,NODE_END | Cost: 9"
    assert content == expected_content, (
        f"Incorrect content in {OUTPUT_FILE}.\n"
        f"Expected: '{expected_content}'\n"
        f"Found: '{content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
