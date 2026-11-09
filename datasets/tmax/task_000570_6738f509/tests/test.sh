#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import re
import secrets
import subprocess
from collections import Counter
from pathlib import Path

HOME = Path('/home/user')
CSV_PATH = HOME / 'dataset_edges.csv'
INDEX_PATH = HOME / 'graph_index.json'
RESULT_PATH = HOME / 'path_result.json'


def run_go_artifact():
    go_files = sorted(p for p in HOME.rglob('*.go') if p.is_file())
    assert go_files, 'No Go source files found under /home/user'

    for output in (INDEX_PATH, RESULT_PATH):
        if output.exists():
            output.unlink()

    directories = sorted({p.parent for p in go_files}, key=lambda p: str(p))
    main_re = re.compile(r'\bfunc\s+main\s*\(')
    main_files = []
    for path in go_files:
        try:
            if main_re.search(path.read_text(errors='ignore')):
                main_files.append(path)
        except OSError:
            pass

    attempts = []
    for directory in directories:
        attempts.append((['go', 'run', '.'], directory, None))
        env = os.environ.copy()
        env['GO111MODULE'] = 'off'
        attempts.append((['go', 'run', '.'], directory, env))
    for path in main_files:
        attempts.append((['go', 'run', path.name], path.parent, None))

    logs = []
    # Multiple rounds support valid solutions split into separate index and path programs.
    for _ in range(3):
        for command, cwd, custom_env in attempts:
            try:
                proc = subprocess.run(
                    command,
                    cwd=str(cwd),
                    env=custom_env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=30,
                )
                logs.append(f"{cwd}$ {' '.join(command)} -> {proc.returncode}\n{proc.stdout}")
            except (subprocess.TimeoutExpired, OSError) as exc:
                logs.append(f"{cwd}$ {' '.join(command)} -> {exc}")
            if INDEX_PATH.is_file() and RESULT_PATH.is_file():
                return

    raise AssertionError(
        'Go artifact did not generate both graph_index.json and path_result.json.\n'
        + '\n'.join(logs[-12:])
    )


def write_fixture(rows):
    with CSV_PATH.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['SourceDataset', 'TargetDataset', 'ProcessingTimeHours'])
        writer.writerows(rows)


def expected_shortest(rows):
    graph = {}
    for source, target, cost in rows:
        graph.setdefault(source, []).append((target, int(cost)))

    queue = [(0, 'Raw_Alpha', ['Raw_Alpha'])]
    best = {}
    while queue:
        cost, node, path = heapq.heappop(queue)
        if node in best:
            continue
        best[node] = cost
        if node == 'Final_Omega':
            return cost, path
        for target, edge_cost in graph.get(node, []):
            if target not in best:
                heapq.heappush(queue, (cost + edge_cost, target, path + [target]))
    raise AssertionError('Verifier fixture has no path to Final_Omega')


def validate_index(rows):
    assert INDEX_PATH.exists(), f'File missing: {INDEX_PATH}'
    assert INDEX_PATH.is_file(), f'Path is not a file: {INDEX_PATH}'
    try:
        with INDEX_PATH.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f'File {INDEX_PATH} is not valid JSON')

    assert isinstance(data, dict), f'Root of {INDEX_PATH} must be a JSON object'
    assert 'Raw_Alpha' in data, f"'Raw_Alpha' key missing in {INDEX_PATH}"
    raw_alpha_edges = data['Raw_Alpha']
    assert isinstance(raw_alpha_edges, list), "Value for 'Raw_Alpha' must be an array"
    if raw_alpha_edges:
        assert isinstance(raw_alpha_edges[0], dict), 'Each edge must be an object'
        assert 'target' in raw_alpha_edges[0], "Edge object missing 'target' key"
        assert 'cost' in raw_alpha_edges[0], "Edge object missing 'cost' key"

    expected = {}
    vertices = set()
    for source, target, cost in rows:
        expected.setdefault(source, []).append((target, int(cost)))
        vertices.update((source, target))

    for source, expected_edges in expected.items():
        assert source in data, f'Missing adjacency entry for source {source!r}'
        actual_edges = data[source]
        assert isinstance(actual_edges, list), f'Adjacency entry for {source!r} must be an array'
        normalized = []
        for edge in actual_edges:
            assert isinstance(edge, dict), f'Edge from {source!r} must be an object'
            assert set(edge) == {'target', 'cost'}, f'Edge from {source!r} must contain exactly target and cost'
            assert isinstance(edge['target'], str), 'Edge target must be a string'
            assert type(edge['cost']) is int, 'Edge cost must be an integer'
            normalized.append((edge['target'], edge['cost']))
        assert Counter(normalized) == Counter(expected_edges), f'Incorrect adjacency list for {source!r}'

    for key, value in data.items():
        assert isinstance(key, str), 'All graph index keys must be strings'
        if key not in expected:
            assert key in vertices and value == [], f'Unexpected or nonempty adjacency entry {key!r}'


def validate_result(rows, fixed_expected_path=None, fixed_expected_cost=None):
    assert RESULT_PATH.exists(), f'File missing: {RESULT_PATH}'
    assert RESULT_PATH.is_file(), f'Path is not a file: {RESULT_PATH}'
    try:
        with RESULT_PATH.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f'File {RESULT_PATH} is not valid JSON')

    assert isinstance(data, dict), 'Path result must be a JSON object'
    assert set(data) == {'source', 'target', 'total_time_hours', 'path'}, 'Path result has incorrect schema'
    assert data.get('source') == 'Raw_Alpha', f"Expected source to be 'Raw_Alpha', got {data.get('source')}"
    assert data.get('target') == 'Final_Omega', f"Expected target to be 'Final_Omega', got {data.get('target')}"
    assert type(data.get('total_time_hours')) is int, 'total_time_hours must be an integer'
    assert isinstance(data.get('path'), list) and all(isinstance(x, str) for x in data['path']), 'path must be an array of strings'

    expected_cost, expected_path = expected_shortest(rows)
    assert data.get('total_time_hours') == expected_cost, f'Expected total_time_hours to be {expected_cost}, got {data.get("total_time_hours")}'
    assert data.get('path') == expected_path, f'Expected path {expected_path}, got {data.get("path")}'

    if fixed_expected_cost is not None:
        assert data.get('total_time_hours') == fixed_expected_cost
    if fixed_expected_path is not None:
        assert data.get('path') == fixed_expected_path


def test_go_program_builds_index_and_computes_shortest_path():
    original_rows = [
        ('Raw_Alpha', 'Clean_Alpha', 2),
        ('Clean_Alpha', 'Merged_Data', 5),
        ('Raw_Beta', 'Merged_Data', 3),
        ('Merged_Data', 'Aggregated_Data', 4),
        ('Aggregated_Data', 'Final_Omega', 1),
        ('Clean_Alpha', 'Fast_Track', 1),
        ('Fast_Track', 'Final_Omega', 2),
        ('Raw_Alpha', 'Slow_Track', 10),
        ('Slow_Track', 'Final_Omega', 1),
    ]
    write_fixture(original_rows)
    run_go_artifact()
    validate_index(original_rows)
    validate_result(
        original_rows,
        fixed_expected_cost=5,
        fixed_expected_path=['Raw_Alpha', 'Clean_Alpha', 'Fast_Track', 'Final_Omega'],
    )

    token = secrets.token_hex(6)
    a, b, c, d = [f'Node_{token}_{suffix}' for suffix in ('A', 'B', 'C', 'D')]
    x, y = f'Noise_{token}_X', f'Noise_{token}_Y'
    dynamic_rows = [
        (x, y, 4),
        ('Raw_Alpha', c, 5),
        (a, b, 3),
        (d, 'Final_Omega', 9),
        (b, 'Final_Omega', 2),
        ('Raw_Alpha', a, 2),
        (c, 'Final_Omega', 6),
        ('Raw_Alpha', d, 1),
        (a, 'Final_Omega', 20),
    ]
    write_fixture(dynamic_rows)
    run_go_artifact()
    validate_index(dynamic_rows)
    validate_result(dynamic_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
