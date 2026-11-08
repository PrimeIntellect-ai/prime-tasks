#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

SOURCE = Path('/home/user/compute_path.c')
GRAPH = Path('/home/user/graph_data.csv')
OUTPUT = Path('/home/user/path_output.txt')
EXECUTABLE = Path('/tmp/compute_path_verifier')

CANONICAL_GRAPH = '''N0,N1,2
N0,N2,5
N0,N3,-10
N1,N3,10
X1,N10,2
N2,N10,A
N2,N3,1
N0,N10
N3,N10,5
N0,N10,50
'''

VALID_EDGE = re.compile(r'^(N[0-9]+),(N[0-9]+),([0-9]+)$')


def compile_submission():
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(SOURCE), '-o', str(EXECUTABLE)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'compute_path.c did not compile:\n{result.stderr}'
    assert EXECUTABLE.is_file(), 'Compilation did not produce an executable.'


def run_submission(graph_text):
    GRAPH.write_text(graph_text)
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(EXECUTABLE)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Program exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.exists(), 'The executed program did not create /home/user/path_output.txt.'
    assert OUTPUT.is_file(), '/home/user/path_output.txt is not a file.'


def valid_edges(graph_text):
    edges = {}
    nodes = set()
    for line in graph_text.splitlines():
        match = VALID_EDGE.fullmatch(line)
        if not match:
            continue
        source, target, weight_text = match.groups()
        weight = int(weight_text)
        if weight <= 0:
            continue
        key = (source, target)
        edges[key] = min(edges.get(key, weight), weight)
        nodes.add(source)
        nodes.add(target)
    return edges, nodes


def shortest_distance(graph_text):
    edges, nodes = valid_edges(graph_text)
    adjacency = {}
    for (source, target), weight in edges.items():
        adjacency.setdefault(source, []).append((target, weight))

    distances = {'N0': 0}
    queue = [(0, 'N0')]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == 'N10':
            return distance, edges
        for target, weight in adjacency.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(target, float('inf')):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))
    return None, edges


def assert_correct_output(graph_text):
    expected_distance, edges = shortest_distance(graph_text)
    content = OUTPUT.read_text().strip()

    if expected_distance is None:
        assert content == 'No valid path found', (
            f'Expected no-path output, got {content!r}.'
        )
        return

    lines = content.splitlines()
    assert len(lines) == 2, f'Expected exactly two output lines, got {len(lines)}.'
    path_match = re.fullmatch(r'Path: (N[0-9]+(?:->N[0-9]+)*)', lines[0].strip())
    weight_match = re.fullmatch(r'Weight: ([0-9]+)', lines[1].strip())
    assert path_match, f'Invalid path line: {lines[0]!r}'
    assert weight_match, f'Invalid weight line: {lines[1]!r}'

    path = path_match.group(1).split('->')
    assert path[0] == 'N0' and path[-1] == 'N10', 'Path must run from N0 to N10.'
    assert len(path) == len(set(path)), 'A shortest positive-weight path must not repeat nodes.'

    actual_weight = 0
    for source, target in zip(path, path[1:]):
        assert (source, target) in edges, f'Output uses invalid or nonexistent edge {source}->{target}.'
        actual_weight += edges[(source, target)]

    reported_weight = int(weight_match.group(1))
    assert reported_weight == actual_weight, 'Reported weight does not equal the path edge sum.'
    assert actual_weight == expected_distance, (
        f'Path weight {actual_weight} is not the shortest distance {expected_distance}.'
    )


@pytest.fixture(scope='session', autouse=True)
def compiled_submission():
    compile_submission()


def test_c_source_file_exists():
    file_path = '/home/user/compute_path.c'
    assert os.path.exists(file_path), f'C source file {file_path} is missing.'
    assert os.path.isfile(file_path), f'{file_path} is not a file.'


def test_output_file_exists():
    run_submission(CANONICAL_GRAPH)
    file_path = '/home/user/path_output.txt'
    assert os.path.exists(file_path), f'Output file {file_path} is missing. Did the C program run?'
    assert os.path.isfile(file_path), f'{file_path} is not a file.'


def test_output_file_content():
    run_submission(CANONICAL_GRAPH)
    file_path = '/home/user/path_output.txt'
    expected_lines = [
        'Path: N0->N2->N3->N10',
        'Weight: 11'
    ]

    with open(file_path, 'r') as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, f'Output file {file_path} must contain exactly two lines, got {len(content)}.'
    assert content[0].strip() == expected_lines[0], f"First line of output is incorrect. Expected '{expected_lines[0]}', got '{content[0].strip()}'."
    assert content[1].strip() == expected_lines[1], f"Second line of output is incorrect. Expected '{expected_lines[1]}', got '{content[1].strip()}'."


def test_strict_schema_filtering():
    graph_text = '''N0,N4,7
N4,N10,8
N0,N10,0
N0,N10,-5
X0,N10,1
N0,X10,1
N0, N10,1
N0,N10, 1
N0,N10,1 
N0,N10,+1
N0,N10,1,extra
N0,N10
n0,N10,1
N0,Nx,1
'''
    run_submission(graph_text)
    assert_correct_output(graph_text)


def test_no_valid_path_and_stale_output_is_replaced():
    graph_text = '''N0,N1,4
N1,N10,0
N1,N10,-2
N1, N10,1
X1,N10,1
N2,N10,3
N0,N2,broken
'''
    run_submission(graph_text)
    assert_correct_output(graph_text)


def test_randomized_graph():
    rng = random.SystemRandom()
    edge_map = {}

    def add(source, target, weight):
        edge_map[(source, target)] = weight

    add('N0', 'N1', rng.randint(2, 20))
    add('N1', 'N5', rng.randint(2, 20))
    add('N5', 'N10', rng.randint(2, 20))

    nodes = [f'N{i}' for i in range(11)]
    for _ in range(35):
        source = rng.choice(nodes)
        target = rng.choice(nodes)
        if source != target:
            add(source, target, rng.randint(1, 40))

    lines = [f'{source},{target},{weight}' for (source, target), weight in edge_map.items()]
    lines.extend([
        'N0,N10,-1',
        'N0,N10,0',
        'N0, N10,1',
        'N0,N10,1,garbage',
        'bad,N10,1',
        'N0,N10,not-a-number',
    ])
    rng.shuffle(lines)
    graph_text = '\n'.join(lines) + '\n'
    run_submission(graph_text)
    assert_correct_output(graph_text)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
