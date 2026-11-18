#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/graph_processor')
DATASET = Path('/home/user/dataset.jsonl')
DB = Path('/home/user/graph.db')
TOP = Path('/home/user/top_nodes.txt')


def run_processor():
    for path in (DB, TOP):
        if path.exists():
            path.unlink()

    result = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f'cargo run failed:\n{result.stdout}'


def expected_graph(records):
    nodes = set()
    edges = set()
    for record in records:
        researcher = record['researcher']
        nodes.add(researcher)
        for collaborator in record['collaborators']:
            nodes.add(collaborator)
            if researcher != collaborator:
                edges.add(tuple(sorted((researcher, collaborator))))
    return nodes, edges


def expected_top(records):
    nodes, edges = expected_graph(records)
    degree = {name: 0 for name in nodes}
    for left, right in edges:
        degree[left] += 1
        degree[right] += 1
    ranked = sorted(degree.items(), key=lambda item: (-item[1], item[0]))[:3]
    return '\n'.join(f'{index}. {name} - {value}' for index, (name, value) in enumerate(ranked, 1)) + '\n'


def assert_top_nodes_file_content(expected_content):
    top_nodes_path = '/home/user/top_nodes.txt'
    assert os.path.isfile(top_nodes_path), f'Expected output file at {top_nodes_path} is missing.'

    expected_lines = [line.strip() for line in expected_content.strip().split('\n')]
    with open(top_nodes_path, 'r') as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n')]

    assert actual_lines == expected_lines, (
        f'Content of {top_nodes_path} is incorrect.\n'
        f'Expected:\n{expected_lines}\nGot:\n{actual_lines}'
    )


def assert_graph_db_exists():
    db_path = '/home/user/graph.db'
    assert os.path.isfile(db_path), f'Expected SQLite database at {db_path} is missing.'
    assert os.path.getsize(db_path) > 0, f'SQLite database at {db_path} is empty.'


def assert_materialized_graph(records):
    expected_nodes, expected_edges = expected_graph(records)
    connection = sqlite3.connect(str(DB))
    try:
        integrity = connection.execute('PRAGMA integrity_check').fetchone()
        assert integrity == ('ok',), f'graph.db failed SQLite integrity_check: {integrity}'

        table_names = [
            row[0] for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        ]
        assert table_names, 'graph.db contains no user tables.'

        tables = []
        id_to_names = {}
        seen_names = set()
        for table in table_names:
            quoted = '"' + table.replace('"', '""') + '"'
            columns = [row[1] for row in connection.execute(f'PRAGMA table_info({quoted})')]
            rows = connection.execute(f'SELECT * FROM {quoted}').fetchall()
            tables.append((columns, rows))

            for row in rows:
                row_names = {value for value in row if isinstance(value, str) and value in expected_nodes}
                seen_names.update(row_names)
                if row_names:
                    for column, value in zip(columns, row):
                        lower = column.lower()
                        if isinstance(value, int) and (lower == 'id' or lower.endswith('_id')):
                            id_to_names.setdefault(value, set()).update(row_names)

        assert seen_names == expected_nodes, (
            f'Database does not materialize every researcher. '
            f'Missing: {sorted(expected_nodes - seen_names)}'
        )

        found_edges = set()
        aggregate_words = ('degree', 'count', 'centrality', 'rank', 'total')
        for columns, rows in tables:
            for row in rows:
                endpoint_names = set()
                for column, value in zip(columns, row):
                    lower = column.lower()
                    if lower == 'id' or any(word in lower for word in aggregate_words):
                        continue
                    if isinstance(value, str) and value in expected_nodes:
                        endpoint_names.add(value)
                    elif isinstance(value, int):
                        endpoint_names.update(id_to_names.get(value, ()))
                for left, right in itertools.combinations(sorted(endpoint_names), 2):
                    found_edges.add((left, right))

        assert found_edges == expected_edges, (
            'SQLite relationship data does not match the undirected input graph. '
            f'Missing: {sorted(expected_edges - found_edges)}; '
            f'Unexpected: {sorted(found_edges - expected_edges)}'
        )
    finally:
        connection.close()


def assert_required_sql_implementation():
    source = '\n'.join(path.read_text(errors='replace') for path in PROJECT.rglob('*.rs'))
    assert re.search(r'GROUP\s+BY', source, re.IGNORECASE), 'Rust project does not use SQL GROUP BY aggregation.'
    assert re.search(r'COUNT\s*\(', source, re.IGNORECASE), 'Rust project does not use SQL COUNT aggregation.'
    assert re.search(r'\bDISTINCT\b', source, re.IGNORECASE), 'Rust project does not count unique collaborators in SQL.'
    assert re.search(r'(\?|:[A-Za-z_][A-Za-z0-9_]*)', source), 'No SQL parameter placeholders were found.'
    assert re.search(r'\.(execute|query|query_map|query_row)\s*\(', source), 'No parameter-capable SQLite query call was found.'


def test_processor_end_to_end():
    original_dataset = DATASET.read_bytes()
    original_records = [json.loads(line) for line in original_dataset.decode().splitlines() if line.strip()]

    assert_required_sql_implementation()

    try:
        run_processor()

        # Preserve the original verifier's exact expected-output assertion.
        assert_top_nodes_file_content('1. Alice - 4\n2. Bob - 3\n3. Dave - 3\n')
        assert_graph_db_exists()
        assert_materialized_graph(original_records)

        dynamic_records = [
            {'researcher': "O'Reilly", 'collaborators': ['Ada', 'Lin', 'Ada']},
            {'researcher': 'Ada', 'collaborators': ['Turing', 'M;DROP']},
            {'researcher': 'Lin', 'collaborators': ['Turing', "O'Reilly"]},
            {'researcher': 'Turing', 'collaborators': ['M;DROP']},
            {'researcher': 'M;DROP', 'collaborators': []},
        ]
        DATASET.write_text(''.join(json.dumps(record) + '\n' for record in dynamic_records))
        run_processor()
        assert_top_nodes_file_content(expected_top(dynamic_records))
        assert_graph_db_exists()
        assert_materialized_graph(dynamic_records)
    finally:
        DATASET.write_bytes(original_dataset)
        try:
            run_processor()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
