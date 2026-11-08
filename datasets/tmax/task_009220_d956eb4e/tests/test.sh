#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_pipeline.py
import collections
import json
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess

WORKSPACE = Path('/home/user/workspace')
DATASET = Path('/home/user/dataset/citations.jsonl')
DB_PATH = WORKSPACE / 'graph.db'
JSON_PATH = WORKSPACE / 'centrality_results.json'

FIXED_RECORDS = [
    {'paper_id': 'P1', 'cites': ['P2', 'P3']},
    {'paper_id': 'P2', 'cites': ['P3']},
    {'paper_id': 'P3', 'cites': ['P1', 'P4']},
    {'paper_id': 'P4', 'cites': []},
    {'paper_id': 'P5', 'cites': ['P1', 'P4']},
]
FIXED_RESULTS = [
    {'node': 'P1', 'degree_centrality': 4},
    {'node': 'P3', 'degree_centrality': 4},
    {'node': 'P2', 'degree_centrality': 2},
    {'node': 'P4', 'degree_centrality': 2},
    {'node': 'P5', 'degree_centrality': 2},
]


def load_json_result():
    assert JSON_PATH.is_file(), f'Results JSON not found at {JSON_PATH}'
    with JSON_PATH.open(encoding='utf-8') as f:
        return json.load(f)


def check_original_final_state():
    # Preserve the original verifier's final-state assertions before replacing outputs.
    assert DB_PATH.is_file(), f'Database not found at {DB_PATH}'
    with sqlite3.connect(DB_PATH) as conn:
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert 'Papers' in tables, "Table 'Papers' is missing in the database"
        assert 'Citations' in tables, "Table 'Citations' is missing in the database"
        assert conn.execute('SELECT COUNT(*) FROM Citations').fetchone()[0] == 7
        assert conn.execute('SELECT COUNT(*) FROM Papers').fetchone()[0] >= 5

    data = load_json_result()
    assert 'metrics' in data
    assert isinstance(data['metrics'], list)
    assert len(data['metrics']) == 5
    for actual, expected in zip(data['metrics'], FIXED_RESULTS):
        assert 'node' in actual and 'degree_centrality' in actual
        assert actual['node'] == expected['node']
        assert actual['degree_centrality'] == expected['degree_centrality']


def compile_submission():
    assert WORKSPACE.is_dir(), f'Workspace not found at {WORKSPACE}'
    sources = []
    for p in WORKSPACE.rglob('*.cpp'):
        if not any(part in {'build', 'CMakeFiles', '.git'} for part in p.parts):
            sources.append(p)
    sources = sorted(set(sources))
    assert sources, 'No C++ source file was found in the workspace'

    preferred = WORKSPACE / 'analyze.cpp'
    attempts = []
    if len(sources) > 1:
        attempts.append(sources)
    if preferred in sources:
        attempts.append([preferred])
    attempts.extend([[p] for p in sources])

    unique_attempts = []
    seen = set()
    for attempt in attempts:
        key = tuple(str(p) for p in attempt)
        if key not in seen:
            seen.add(key)
            unique_attempts.append(attempt)

    executable = Path('/tmp/submitted_analyzer')
    errors = []
    for attempt in unique_attempts:
        executable.unlink(missing_ok=True)
        cmd = ['g++', '-std=c++17', '-O2', '-o', str(executable)] + [str(p) for p in attempt] + ['-lsqlite3']
        result = subprocess.run(cmd, cwd=WORKSPACE, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
        if result.returncode == 0 and executable.is_file():
            return executable
        errors.append(result.stdout[-2000:])
    raise AssertionError('Could not compile the submitted C++ program:\n' + '\n'.join(errors))


def expected_for(records):
    nodes = set()
    edges = []
    for record in records:
        source = record['paper_id']
        nodes.add(source)
        for target in record['cites']:
            nodes.add(target)
            edges.append((source, target))
    degree = {node: 0 for node in nodes}
    for source, target in edges:
        degree[source] += 1
        degree[target] += 1
    metrics = [
        {'node': node, 'degree_centrality': degree[node]}
        for node in nodes
    ]
    metrics.sort(key=lambda item: (-item['degree_centrality'], item['node']))
    return nodes, edges, metrics


def write_dataset(records):
    DATASET.parent.mkdir(parents=True, exist_ok=True)
    with DATASET.open('w', encoding='utf-8') as f:
        for record in records:
            f.write(json.dumps(record, separators=(',', ':')) + '\n')


def run_and_validate(executable, records):
    write_dataset(records)
    DB_PATH.unlink(missing_ok=True)
    JSON_PATH.unlink(missing_ok=True)

    result = subprocess.run([str(executable)], cwd=WORKSPACE, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, 'C++ program failed:\n' + result.stdout[-4000:]

    expected_nodes, expected_edges, expected_metrics = expected_for(records)
    assert DB_PATH.is_file(), f'Database not generated at {DB_PATH}'
    with sqlite3.connect(DB_PATH) as conn:
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert 'Papers' in tables, "Table 'Papers' is missing"
        assert 'Citations' in tables, "Table 'Citations' is missing"

        papers_schema = conn.execute("PRAGMA table_info('Papers')").fetchall()
        citations_schema = conn.execute("PRAGMA table_info('Citations')").fetchall()
        assert len(papers_schema) == 1
        assert papers_schema[0][1] == 'id' and papers_schema[0][2].upper() == 'TEXT' and papers_schema[0][5] == 1
        assert [(r[1], r[2].upper()) for r in citations_schema] == [('source', 'TEXT'), ('target', 'TEXT')]

        actual_nodes = [r[0] for r in conn.execute('SELECT id FROM Papers')]
        actual_edges = [tuple(r) for r in conn.execute('SELECT source, target FROM Citations')]
        assert collections.Counter(actual_nodes) == collections.Counter(expected_nodes)
        assert collections.Counter(actual_edges) == collections.Counter(expected_edges)

    data = load_json_result()
    assert isinstance(data, dict) and set(data) == {'metrics'}
    metrics = data['metrics']
    assert isinstance(metrics, list)
    assert metrics == expected_metrics
    for metric in metrics:
        assert isinstance(metric, dict) and set(metric) == {'node', 'degree_centrality'}
        assert isinstance(metric['node'], str)
        assert isinstance(metric['degree_centrality'], int) and not isinstance(metric['degree_centrality'], bool)


def main():
    check_original_final_state()
    executable = compile_submission()

    # Re-run the compiled C++ pipeline on the required mock data.
    run_and_validate(executable, FIXED_RECORDS)

    # Exercise the same pipeline on an unpredictable dataset, including an isolated
    # primary paper and a cited-only paper.
    token = secrets.token_hex(6)
    names = [f'node_{token}_{letter}' for letter in 'ABCDEFG']
    cited_only = f'cited_only_{token}'
    a, b, c, d, e, f, g = names
    dynamic_records = [
        {'paper_id': a, 'cites': [b, c, cited_only]},
        {'paper_id': b, 'cites': [c, d]},
        {'paper_id': c, 'cites': [a]},
        {'paper_id': d, 'cites': [cited_only]},
        {'paper_id': e, 'cites': [a, d]},
        {'paper_id': f, 'cites': [e]},
        {'paper_id': g, 'cites': []},
    ]
    run_and_validate(executable, dynamic_records)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
