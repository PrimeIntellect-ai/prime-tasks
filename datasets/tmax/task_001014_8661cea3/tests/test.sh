#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
GO_FILE = HOME / 'etl.go'
DB_FILE = HOME / 'topology.db'
IMPACT_FILE = HOME / 'impact.json'

TRUTH = {
    'Gateway': 6,
    'Auth': 2,
    'Cart': 2,
    'Catalog': 2,
    'Inventory': 1,
    'DB': 0,
    'Redis': 0,
}


def clean_name(value):
    value = str(value).strip().strip('.,;:!?\"\'')
    return re.sub(r'^service\s+', '', value, flags=re.I).strip()


def read_impact():
    with IMPACT_FILE.open() as f:
        return json.load(f)


def run_etl():
    DB_FILE.unlink(missing_ok=True)
    IMPACT_FILE.unlink(missing_ok=True)
    result = subprocess.run(
        ['go', 'run', str(GO_FILE)], cwd=str(HOME),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, 'etl.go failed:\n' + result.stdout
    assert DB_FILE.is_file(), 'Running etl.go did not create /home/user/topology.db'
    assert IMPACT_FILE.is_file(), 'Running etl.go did not create /home/user/impact.json'


def database_graphs():
    graphs = []
    with sqlite3.connect(str(DB_FILE)) as conn:
        tables = [r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )]
        for table in tables:
            escaped_table = table.replace('"', '""')
            columns = [r[1] for r in conn.execute(f'PRAGMA table_info("{escaped_table}")')]
            for i, source_col in enumerate(columns):
                for j, target_col in enumerate(columns):
                    if i == j:
                        continue
                    es = source_col.replace('"', '""')
                    et = target_col.replace('"', '""')
                    try:
                        rows = conn.execute(
                            f'SELECT "{es}", "{et}" FROM "{escaped_table}" '
                            f'WHERE "{es}" IS NOT NULL AND "{et}" IS NOT NULL LIMIT 10000'
                        ).fetchall()
                    except sqlite3.Error:
                        continue
                    edges = {(clean_name(a), clean_name(b)) for a, b in rows}
                    edges = {(a, b) for a, b in edges if a and b and a != b}
                    if edges:
                        graphs.append((table, source_col, target_col, edges))
    return graphs


def impacts_from_edges(edges):
    nodes = {x for edge in edges for x in edge}
    adjacency = {node: set() for node in nodes}
    for source, target in edges:
        adjacency[source].add(target)
    result = {}
    for source in nodes:
        seen = set()
        stack = list(adjacency[source])
        while stack:
            node = stack.pop()
            if node == source or node in seen:
                continue
            seen.add(node)
            stack.extend(adjacency.get(node, ()))
        result[source] = len(seen)
    return result


def transcript_candidates(source):
    candidates = set()
    for root in (HOME, Path('/app')):
        for path in root.rglob('*'):
            if path.is_file() and (path.suffix.lower() in ('.txt', '.text') or 'transcript' in path.name.lower()):
                candidates.add(path)

    for literal in re.findall(r'[\"`]([^\"`\n]*(?:transcript[^\"`\n]*|[^\"`\n]+\.(?:txt|text)))[\"`]', source, re.I):
        path = Path(literal)
        if not path.is_absolute():
            path = HOME / path
        if path.is_file():
            candidates.add(path)
    return sorted(candidates)


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_etl():
    assert GO_FILE.is_file(), 'Expected /home/user/etl.go is missing or is not a file'
    source = GO_FILE.read_text(errors='replace')
    assert re.search(r'\bpackage\s+main\b', source), 'etl.go is not a Go main package'
    assert re.search(r'\bfunc\s+main\s*\(', source), 'etl.go has no main function'
    assert 'github.com/mattn/go-sqlite3' in source, 'etl.go must use github.com/mattn/go-sqlite3'
    assert re.search(r'\bWITH\s+RECURSIVE\b', source, re.I | re.S), 'etl.go does not contain the required recursive CTE'
    assert re.search(r'\bINSERT\s+INTO\b', source, re.I | re.S), 'etl.go does not insert parsed edges into SQLite'

    candidates = transcript_candidates(source)
    usable = []
    for path in candidates:
        try:
            text = path.read_text(errors='replace')
        except OSError:
            continue
        if re.search(r'\bcalls?\b', text, re.I):
            usable.append(path)
    assert usable, 'No generated text transcript containing dependency statements was found'

    synthetic_text = (
        'Service Quartz calls Service Ruby. '
        'Service Quartz calls Service Sapphire. '
        'Service Ruby calls Service Topaz. '
        'Service Sapphire calls Service Topaz.\n'
    )
    synthetic_edges = {
        ('Quartz', 'Ruby'), ('Quartz', 'Sapphire'),
        ('Ruby', 'Topaz'), ('Sapphire', 'Topaz'),
    }
    synthetic_impact = {'Quartz': 3, 'Ruby': 1, 'Sapphire': 1, 'Topaz': 0}
    backups = {path: path.read_bytes() for path in usable}

    try:
        for path in usable:
            path.write_text(synthetic_text)
        run_etl()
        predicted = read_impact()
        for service, expected in synthetic_impact.items():
            assert service in predicted, f'etl.go did not parse synthetic transcript service {service}'
            assert predicted[service] == expected, (
                f'Wrong synthetic impact for {service}: expected {expected}, got {predicted[service]}'
            )
        assert any(synthetic_edges.issubset(edges) for _, _, _, edges in database_graphs()), (
            'The SQLite database does not contain the edges parsed from the synthetic transcript'
        )
    finally:
        for path, data in backups.items():
            path.write_bytes(data)

    # Leave the requested artifacts freshly generated from the real transcript.
    run_etl()


def test_impact_json_exists():
    impact_path = '/home/user/impact.json'
    assert os.path.exists(impact_path), f'Expected output file {impact_path} is missing.'
    assert os.path.isfile(impact_path), f'Path {impact_path} is not a file.'


def test_impact_mae():
    impact_path = '/home/user/impact.json'
    try:
        with open(impact_path, 'r') as f:
            predicted = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read or parse {impact_path} as JSON: {e}')

    errors = []
    for k, v in TRUTH.items():
        pred_val = predicted.get(k, 0)
        if not isinstance(pred_val, (int, float)):
            try:
                pred_val = float(pred_val)
            except (ValueError, TypeError):
                pytest.fail(f'Predicted value for {k} is not a number: {pred_val}')
        errors.append(abs(v - pred_val))

    mae = sum(errors) / len(TRUTH)
    assert mae <= 1.5, f'Mean Absolute Error (MAE) is {mae}, which is greater than the threshold of 1.5. Predicted: {predicted}'


def test_database_matches_exported_impacts():
    predicted = read_impact()
    graphs = database_graphs()
    assert graphs, 'topology.db has no usable directed edge table'

    matching_graph = False
    for _, _, _, edges in graphs:
        computed = impacts_from_edges(edges)
        if computed and all(
            service in predicted
            and isinstance(predicted[service], (int, float))
            and predicted[service] == count
            for service, count in computed.items()
        ):
            matching_graph = True
            break
    assert matching_graph, 'impact.json is not the recursive reachability result of the edges stored in topology.db'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
