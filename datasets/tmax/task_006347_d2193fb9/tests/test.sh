#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
NODES = HOME / 'nodes.csv'
EDGES = HOME / 'edges.csv'
OUTPUT = HOME / 'path.csv'
SOURCE = HOME / 'graph_solver.cpp'
EXECUTABLE = HOME / 'graph_solver'
COMPILED = Path('/tmp/graph_solver_from_source')


def test_path_csv_exists_and_correct():
    path_csv = '/home/user/path.csv'
    assert os.path.isfile(path_csv), f'Output file {path_csv} does not exist. Did you run your C++ program?'

    expected_content = '''step,node_id,node_name,cumulative_weight
0,1,START,0
1,4,GAMMA,2
2,5,DELTA,4
3,6,END,8'''

    with open(path_csv, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f'Content of {path_csv} does not match the expected shortest path output.'


def test_cpp_source_exists():
    cpp_file = '/home/user/graph_solver.cpp'
    assert os.path.isfile(cpp_file), f'C++ source file {cpp_file} is missing.'


def test_executable_exists():
    executable = '/home/user/graph_solver'
    assert os.path.isfile(executable), f'Compiled executable {executable} is missing.'
    assert os.access(executable, os.X_OK), f'File {executable} is not executable.'


def make_case(rng):
    roles = ['S', 'A', 'B', 'C', 'E', 'Z']
    values = rng.sample(range(100, 1000), len(roles))
    ids = dict(zip(roles, values))
    names = {
        'S': 'START', 'A': 'ALPHA', 'B': 'BETA',
        'C': 'GAMMA', 'E': 'END', 'Z': 'DELTA'
    }
    node_rows = [(ids[r], names[r]) for r in roles]
    rng.shuffle(node_rows)

    p, q, r = (rng.randint(2, 8) for _ in range(3))
    shortest = p + q + r
    base_ts = rng.randint(1000, 9000)
    edge_rows = [
        # This stale edge would create an incorrectly cheap path if retained.
        (ids['S'], ids['A'], 1, base_ts),
        (ids['S'], ids['A'], shortest + 8, base_ts + 40),
        (ids['A'], ids['E'], 1, base_ts + 5),
        (ids['S'], ids['B'], p, base_ts + 10),
        # This pair checks that a newer edge can also be cheaper.
        (ids['B'], ids['C'], shortest + 30, base_ts + 2),
        (ids['B'], ids['C'], q, base_ts + 50),
        (ids['C'], ids['E'], r, base_ts + 20),
        (ids['S'], ids['E'], shortest + 10, base_ts + 30),
        (ids['B'], ids['E'], q + r + 8, base_ts + 60),
        (ids['E'], ids['S'], 1, base_ts + 70),
        (ids['Z'], ids['E'], 1, base_ts + 80),
    ]
    rng.shuffle(edge_rows)
    return node_rows, edge_rows


def write_case(node_rows, edge_rows):
    with NODES.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'name'])
        writer.writerows(node_rows)
    with EDGES.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['src', 'dst', 'weight', 'timestamp'])
        writer.writerows(edge_rows)


def latest_edges(edge_rows):
    latest = {}
    for src, dst, weight, timestamp in edge_rows:
        key = (src, dst)
        if key not in latest or timestamp > latest[key][1]:
            latest[key] = (weight, timestamp)
    return {key: value[0] for key, value in latest.items()}


def shortest_distance(start, end, valid_edges):
    graph = {}
    for (src, dst), weight in valid_edges.items():
        graph.setdefault(src, []).append((dst, weight))
    distances = {start: 0}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        if node == end:
            return distance
        for nxt, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(nxt, float('inf')):
                distances[nxt] = candidate
                heapq.heappush(queue, (candidate, nxt))
    raise AssertionError('Generated test case unexpectedly has no START-to-END path')


def validate_output(node_rows, edge_rows):
    assert OUTPUT.is_file(), 'The solver did not create /home/user/path.csv'
    with OUTPUT.open(newline='') as f:
        rows = list(csv.reader(f))

    assert rows, 'path.csv is empty'
    assert rows[0] == ['step', 'node_id', 'node_name', 'cumulative_weight'], 'path.csv has an incorrect header'
    assert len(rows) >= 2, 'path.csv contains no path'

    id_to_name = {node_id: name for node_id, name in node_rows}
    start = next(node_id for node_id, name in node_rows if name == 'START')
    end = next(node_id for node_id, name in node_rows if name == 'END')
    valid_edges = latest_edges(edge_rows)
    expected_distance = shortest_distance(start, end, valid_edges)

    parsed = []
    for index, row in enumerate(rows[1:]):
        assert len(row) == 4, f'Path row {index + 1} does not have four columns'
        try:
            step, node_id, cumulative = int(row[0]), int(row[1]), int(row[3])
        except ValueError as exc:
            raise AssertionError(f'Path row {index + 1} contains a non-integer numeric field') from exc
        assert step == index, 'Path steps must begin at zero and be consecutive'
        assert node_id in id_to_name, f'Unknown node id {node_id} in path.csv'
        assert row[2] == id_to_name[node_id], f'Incorrect node name for id {node_id}'
        parsed.append((node_id, cumulative))

    assert parsed[0] == (start, 0), 'The path must begin at START with cumulative weight zero'
    assert parsed[-1][0] == end, 'The path must end at END'

    cumulative = 0
    for index in range(1, len(parsed)):
        src = parsed[index - 1][0]
        dst = parsed[index][0]
        assert (src, dst) in valid_edges, f'Path uses nonexistent or stale-only edge {src}->{dst}'
        cumulative += valid_edges[(src, dst)]
        assert parsed[index][1] == cumulative, 'Incorrect cumulative_weight in path.csv'
    assert cumulative == expected_distance, 'The emitted path is not a shortest path'


def run_and_check(program, node_rows, edge_rows):
    write_case(node_rows, edge_rows)
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(program)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, f'{program} failed: {result.stderr}'
    validate_output(node_rows, edge_rows)


def test_executable_and_source_on_altered_inputs():
    compile_result = subprocess.run(
        ['g++', '-O3', '-std=c++17', str(SOURCE), '-o', str(COMPILED)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f'graph_solver.cpp does not compile: {compile_result.stderr}'
    assert COMPILED.is_file() and os.access(COMPILED, os.X_OK)

    originals = {
        NODES: NODES.read_bytes(),
        EDGES: EDGES.read_bytes(),
        OUTPUT: OUTPUT.read_bytes() if OUTPUT.exists() else None,
    }
    rng = random.SystemRandom()
    try:
        for program in (EXECUTABLE, COMPILED):
            for _ in range(3):
                node_rows, edge_rows = make_case(rng)
                run_and_check(program, node_rows, edge_rows)
    finally:
        NODES.write_bytes(originals[NODES])
        EDGES.write_bytes(originals[EDGES])
        if originals[OUTPUT] is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(originals[OUTPUT])

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
