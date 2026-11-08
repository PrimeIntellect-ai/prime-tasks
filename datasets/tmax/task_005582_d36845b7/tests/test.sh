#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import sqlite3
import subprocess
from collections import Counter
from pathlib import Path

import pytest

PROJECT = Path('/home/user/graph_analyzer')
NODES = Path('/home/user/nodes.csv')
EDGES = Path('/home/user/edges.csv')
DB = Path('/home/user/graph.db')
RESULTS = Path('/home/user/results.json')


def run_application():
    DB.unlink(missing_ok=True)
    RESULTS.unlink(missing_ok=True)
    proc = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert proc.returncode == 0, f'cargo run failed:\n{proc.stdout}'
    assert DB.is_file(), 'The Rust application did not create /home/user/graph.db.'
    assert RESULTS.is_file(), 'The Rust application did not create /home/user/results.json.'


def read_csv(path):
    with path.open(newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def expected_paths(edge_rows):
    edges = [(r['source'], r['target'], float(r['weight'])) for r in edge_rows]
    return [
        (s1, t2, w1 + w2)
        for s1, t1, w1 in edges
        for s2, t2, w2 in edges
        if t1 == s2
    ]


def assert_weighted_rows(actual, expected):
    def normalized(rows):
        return Counter((a, b, round(float(w), 9)) for a, b, w in rows)
    assert normalized(actual) == normalized(expected)


def load_and_validate_results(expected):
    assert RESULTS.is_file(), f'Results file {RESULTS} does not exist.'
    try:
        with RESULTS.open(encoding='utf-8') as f:
            results = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {RESULTS} is not valid JSON: {exc}')

    assert isinstance(results, list), 'results.json must contain a JSON array.'
    for item in results:
        assert isinstance(item, dict), 'Every result must be a JSON object.'
        assert set(item) == {'destination', 'weight'}, 'Result objects must contain only destination and weight.'
        assert isinstance(item['destination'], str), 'destination must be a string.'
        assert isinstance(item['weight'], float), 'weight must be encoded as a JSON floating-point number.'
        assert math.isfinite(item['weight']), 'weight must be finite.'
    assert results == expected


def validate_database(node_rows, edge_rows):
    assert DB.is_file(), f'Database file {DB} does not exist.'
    expected_node_rows = [(r['id'], r['name']) for r in node_rows]
    expected_edge_rows = [(r['source'], r['target'], float(r['weight'])) for r in edge_rows]
    expected_two_hops = expected_paths(edge_rows)

    with sqlite3.connect(DB) as conn:
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert 'nodes' in tables, "Table 'nodes' does not exist in the database."
        assert 'edges' in tables, "Table 'edges' does not exist in the database."
        assert 'two_hop_paths' in tables, "Table 'two_hop_paths' does not exist in the database."

        assert Counter(conn.execute('SELECT id, name FROM nodes')) == Counter(expected_node_rows), \
            'The nodes table does not exactly match nodes.csv.'
        assert_weighted_rows(conn.execute('SELECT source, target, weight FROM edges'), expected_edge_rows)

        index_rows = list(conn.execute("PRAGMA index_list('edges')"))
        assert len(index_rows) > 0, "No indexes were created on the 'edges' table."
        indexed_columns = []
        for index_row in index_rows:
            name = index_row[1]
            cols = [r[2] for r in conn.execute(f"PRAGMA index_info('{name.replace(chr(39), chr(39) * 2)}')")]
            if cols:
                indexed_columns.append(cols)
        assert any(cols[0] == 'source' for cols in indexed_columns), \
            "No edges index supports outgoing-edge lookup by source."
        assert any(cols[0] == 'target' for cols in indexed_columns), \
            "No edges index supports incoming-edge lookup by target."

        columns = [row[1] for row in conn.execute('PRAGMA table_info(two_hop_paths)')]
        assert 'start_node' in columns, "Column 'start_node' missing from 'two_hop_paths'."
        assert 'end_node' in columns, "Column 'end_node' missing from 'two_hop_paths'."
        assert 'total_weight' in columns, "Column 'total_weight' missing from 'two_hop_paths'."

        actual_paths = list(conn.execute(
            'SELECT start_node, end_node, total_weight FROM two_hop_paths'
        ))
        assert len(actual_paths) > 0, "Table 'two_hop_paths' is empty."
        assert_weighted_rows(actual_paths, expected_two_hops)


def test_project_directory_and_rust_implementation_exist():
    assert PROJECT.is_dir(), f'Project directory {PROJECT} does not exist.'
    cargo_toml = PROJECT / 'Cargo.toml'
    assert cargo_toml.is_file(), 'Cargo.toml not found in the project directory.'
    assert re.search(r'(?m)^\s*name\s*=\s*["\']graph_analyzer["\']', cargo_toml.read_text(encoding='utf-8')), \
        'The Cargo package is not named graph_analyzer.'

    rust_files = [p for p in PROJECT.rglob('*.rs') if 'target' not in p.parts]
    assert rust_files, 'No Rust source files were found.'
    source = '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in rust_files)

    materialization = re.search(
        r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?two_hop_paths\s+AS\s+(?:WITH\b.*?SELECT|SELECT)\b(.*?);',
        source,
        re.IGNORECASE | re.DOTALL,
    )
    assert materialization, \
        'Rust source must materialize two_hop_paths with one CREATE TABLE ... AS SELECT statement.'
    statement = materialization.group(0)
    assert len(re.findall(r'\bedges\b', statement, re.IGNORECASE)) >= 2, \
        'The materialization statement must join two instances of edges.'
    assert re.search(r'\bJOIN\b', statement, re.IGNORECASE), \
        'The materialization statement must perform the two-edge join in SQL.'

    assert re.search(
        r'FROM\s+two_hop_paths\b.*?WHERE\s+start_node\s*=\s*(?:\?(?:\d+)?|[:@$][A-Za-z_]\w*)',
        source,
        re.IGNORECASE | re.DOTALL,
    ), 'The two_hop_paths lookup must use a SQL parameter placeholder.'
    assert re.search(r'ORDER\s+BY\s+total_weight\s+DESC', source, re.IGNORECASE), \
        'The parameterized lookup must order by total_weight descending.'

    string_parameters = re.findall(
        r'fn\s+\w+\s*\([^)]*?\b([A-Za-z_]\w*)\s*:\s*&?\s*(?:str|String)\b',
        source,
        re.IGNORECASE | re.DOTALL,
    )
    assert string_parameters, 'No Rust function taking a starting-node string parameter was found.'
    assert any(re.search(
        rf'(?:params!|named_params!)\s*\[[^\]]*\b{re.escape(param)}\b|\[[^\]]*\b{re.escape(param)}\b[^\]]*\]\s*\)',
        source,
        re.DOTALL,
    ) for param in string_parameters), \
        'The starting-node function parameter is not bound to the SQLite query.'


def test_application_on_original_inputs():
    run_application()


def test_results_json_correct():
    expected_results = [
        {'destination': 'N003', 'weight': 6.0},
        {'destination': 'N005', 'weight': 5.0},
        {'destination': 'N003', 'weight': 4.0},
    ]
    load_and_validate_results(expected_results)


def test_database_indexes_and_materialized_rows_are_correct():
    validate_database(read_csv(NODES), read_csv(EDGES))


def test_application_recomputes_from_changed_csv_inputs():
    original_nodes = NODES.read_bytes()
    original_edges = EDGES.read_bytes()
    try:
        NODES.write_text(
            'id,name\nN001,Root\nA,Alpha\nB,Beta\nC,Gamma\nD,Delta\nY,Yankee\nZ,Zulu\nQ,Quebec\n',
            encoding='utf-8',
        )
        EDGES.write_text(
            'source,target,weight\n'
            'N001,A,1.25\n'
            'A,Z,2.75\n'
            'N001,B,10.0\n'
            'B,Y,-1.0\n'
            'N001,C,3.0\n'
            'C,Z,3.0\n'
            'D,N001,5.0\n'
            'Z,Q,0.5\n',
            encoding='utf-8',
        )
        run_application()
        dynamic_nodes = read_csv(NODES)
        dynamic_edges = read_csv(EDGES)
        validate_database(dynamic_nodes, dynamic_edges)
        load_and_validate_results([
            {'destination': 'Y', 'weight': 9.0},
            {'destination': 'Z', 'weight': 6.0},
            {'destination': 'Z', 'weight': 4.0},
        ])
    finally:
        NODES.write_bytes(original_nodes)
        EDGES.write_bytes(original_edges)
        run_application()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
