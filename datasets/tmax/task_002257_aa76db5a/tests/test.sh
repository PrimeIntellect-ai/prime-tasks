#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
OUTPUT = HOME / 'path.json'
INPUTS = [HOME / 'nodes.csv', HOME / 'edges.csv', HOME / 'tombstones.csv']


def write_case(case):
    with open(HOME / 'nodes.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['node_id', 'name'])
        for node in case['nodes']:
            w.writerow([node, f'Node{node}'])
    with open(HOME / 'edges.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['src', 'dst', 'cost', 'version'])
        w.writerows(case['edges'])
    with open(HOME / 'tombstones.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['src', 'dst', 'version'])
        w.writerows(case['tombstones'])


def filtered_edges(case):
    tomb = {}
    for src, dst, version in case['tombstones']:
        tomb[(src, dst)] = max(tomb.get((src, dst), -1), version)

    selected = {}
    for src, dst, cost, version in case['edges']:
        if tomb.get((src, dst), -1) >= version:
            continue
        key = (src, dst)
        if key not in selected or version > selected[key][1]:
            selected[key] = (cost, version)
    return {key: value[0] for key, value in selected.items()}


def expected_distance(case):
    graph = {}
    for (src, dst), cost in filtered_edges(case).items():
        graph.setdefault(src, []).append((dst, cost))

    dist = {10: 0}
    queue = [(0, 10)]
    while queue:
        value, node = heapq.heappop(queue)
        if value != dist[node]:
            continue
        if node == 42:
            return value
        for nxt, cost in graph.get(node, []):
            candidate = value + cost
            if candidate < dist.get(nxt, float('inf')):
                dist[nxt] = candidate
                heapq.heappush(queue, (candidate, nxt))
    raise AssertionError('Verifier generated an unreachable test case')


def validate_output(case):
    assert OUTPUT.is_file(), 'C program did not create /home/user/path.json'
    with open(OUTPUT, 'r') as f:
        data = json.load(f)

    assert 'cost' in data, "JSON output is missing the 'cost' key."
    assert 'path' in data, "JSON output is missing the 'path' key."
    path = data['path']
    assert isinstance(path, list) and len(path) >= 2, 'path must be a nonempty node list'
    assert path[0] == 10 and path[-1] == 42, 'path must run from node 10 to node 42'
    assert len(path) <= 100, 'path is unreasonably long'

    edges = filtered_edges(case)
    actual_cost = 0
    for src, dst in zip(path, path[1:]):
        assert (src, dst) in edges, f'path uses missing or stale edge {src}->{dst}'
        actual_cost += edges[(src, dst)]

    optimum = expected_distance(case)
    assert data['cost'] == actual_cost, 'reported cost does not equal the path edge costs'
    assert data['cost'] == optimum, 'reported path is not a shortest path'


def generated_case(seed):
    rng = random.Random(seed)
    nodes = [10, 15, 20, 30, 42]
    chain = [(10, 15), (15, 20), (20, 30), (30, 42)]
    edges = []
    tombstones = []

    # Each chain pair has an old row deleted by a tombstone and a newer live row.
    for src, dst in chain:
        edges.append((src, dst, rng.randint(12, 25), 1))
        edges.append((src, dst, rng.randint(1, 8), 2))
        tombstones.append((src, dst, 1))

    for src in nodes:
        for dst in nodes:
            if src == dst or (src, dst) in chain:
                continue
            if rng.random() < 0.42:
                edges.append((src, dst, rng.randint(2, 30), 1))
                if rng.random() < 0.45:
                    edges.append((src, dst, rng.randint(1, 20), 3))
                if rng.random() < 0.35:
                    tombstones.append((src, dst, rng.choice([1, 2, 3, 4])))

    edges.append((10, 42, rng.randint(35, 60), 5))
    return {'nodes': nodes, 'edges': edges, 'tombstones': tombstones}


ORIGINAL_CASE = {
    'nodes': [10, 15, 20, 30, 42],
    'edges': [
        (10, 15, 5, 1), (15, 42, 10, 1), (10, 20, 2, 1),
        (20, 30, 1, 1), (30, 42, 1, 1), (20, 42, 1, 2),
        (20, 42, 5, 1), (10, 42, 100, 1),
    ],
    'tombstones': [(20, 42, 3), (10, 42, 1)],
}


def compile_candidates():
    sources = sorted(HOME.rglob('*.c'))
    assert sources, 'No C source program was found under /home/user'

    main_sources = []
    support_sources = []
    for source in sources:
        text = source.read_text(errors='ignore')
        if re.search(r'\bmain\s*\(', text):
            main_sources.append(source)
        else:
            support_sources.append(source)
    assert main_sources, 'No C source file defining main() was found'

    binaries = []
    for index, main_source in enumerate(main_sources):
        binary = Path(f'/tmp/submission_program_{index}')
        command = ['gcc', '-std=c11', '-O2', '-o', str(binary), str(main_source)]
        command.extend(str(path) for path in support_sources)
        command.append('-lm')
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0:
            binaries.append(binary)
    assert binaries, 'The submitted C program could not be compiled with gcc'
    return binaries


@pytest.fixture(scope='module', autouse=True)
def execute_and_verify_c_program():
    original_inputs = {path: path.read_bytes() for path in INPUTS}
    cases = [ORIGINAL_CASE, generated_case(731), generated_case(1907), generated_case(9919)]
    selected = None

    try:
        for binary in compile_candidates():
            passed = True
            for case in cases:
                try:
                    write_case(case)
                    if OUTPUT.exists():
                        OUTPUT.unlink()
                    result = subprocess.run(
                        [str(binary)], cwd=str(HOME), stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, timeout=5
                    )
                    if result.returncode != 0:
                        raise AssertionError(f'program exited with status {result.returncode}')
                    validate_output(case)
                except Exception:
                    passed = False
                    break
            if passed:
                selected = binary
                break

        assert selected is not None, 'No compiled C program correctly processed the CSV test cases'

        # Execute the accepted program once more on the task's original inputs.
        write_case(ORIGINAL_CASE)
        if OUTPUT.exists():
            OUTPUT.unlink()
        result = subprocess.run(
            [str(selected)], cwd=str(HOME), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5
        )
        assert result.returncode == 0, f'C program exited with status {result.returncode}'
        assert OUTPUT.is_file(), 'C program did not create /home/user/path.json'
    finally:
        for path, contents in original_inputs.items():
            path.write_bytes(contents)

    yield


def test_path_json_exists():
    """Test that the output JSON file was created."""
    file_path = "/home/user/path.json"
    assert os.path.isfile(file_path), f"Output file is missing: {file_path}"


def test_path_json_content():
    """Test that the output JSON file contains the correct shortest path and cost."""
    file_path = "/home/user/path.json"
    assert os.path.isfile(file_path), f"Output file is missing: {file_path}"

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {file_path} as JSON: {e}")

    assert "cost" in data, "JSON output is missing the 'cost' key."
    assert "path" in data, "JSON output is missing the 'path' key."

    expected_cost = 4
    expected_path = [10, 20, 30, 42]

    assert data["cost"] == expected_cost, f"Expected cost to be {expected_cost}, but got {data['cost']}."
    assert data["path"] == expected_path, f"Expected path to be {expected_path}, but got {data['path']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
