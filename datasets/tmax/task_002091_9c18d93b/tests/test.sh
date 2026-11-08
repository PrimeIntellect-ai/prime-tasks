#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import numpy as np
import pytest

SOURCE = '/home/user/pagerank.cpp'
GRAPH = '/home/user/graph.txt'
RESULTS = '/home/user/results.csv'
BINARY = '/home/user/pagerank'

ORIGINAL_GRAPH = '''5
0 1
0 2
1 2
2 3
3 4
4 0
'''

ALTERNATE_GRAPH = '''6
0 1
1 2
2 0
2 3
3 4
4 5
5 3
'''


def expected_pagerank(graph_text):
    lines = [line.strip() for line in graph_text.splitlines() if line.strip()]
    n = int(lines[0])
    adjacency = [set() for _ in range(n)]
    for line in lines[1:]:
        u, v = map(int, line.split())
        adjacency[u].add(v)
        adjacency[v].add(u)

    p = np.zeros((n, n), dtype=float)
    for i, neighbors in enumerate(adjacency):
        assert neighbors, f'Test graph unexpectedly contains isolated node {i}'
        for j in neighbors:
            p[i, j] = 1.0 / len(neighbors)

    d = 0.85
    return np.linalg.solve(
        np.eye(n) - d * p.T,
        np.full(n, (1.0 - d) / n),
    )


def run_and_check(graph_text):
    expected = expected_pagerank(graph_text)
    n = len(expected)

    with open(GRAPH, 'w') as f:
        f.write(graph_text)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        [BINARY],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f'Compiled pagerank program failed with exit code {completed.returncode}. '
        f'stdout: {completed.stdout}\nstderr: {completed.stderr}'
    )
    assert os.path.isfile(RESULTS), 'Running the compiled program did not create /home/user/results.csv.'

    with open(RESULTS, newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, 'results.csv is empty.'
        assert header == ['Node', 'Exact', 'Empirical'], f'Incorrect CSV header: {header}'
        rows = list(reader)

    assert len(rows) == n, f'Expected exactly {n} data rows, but found {len(rows)}.'
    number_format = re.compile(r'^[-+]?\d+\.\d{4}$')

    for i, row in enumerate(rows):
        assert len(row) == 3, f'Row {i} has {len(row)} columns instead of 3.'
        try:
            node = int(row[0])
        except ValueError:
            assert False, f"Node value '{row[0]}' is not an integer."
        assert node == i, f'Expected Node {i}, but got {node}.'

        exact_str, empirical_str = row[1], row[2]
        assert number_format.fullmatch(exact_str), (
            f"Exact value '{exact_str}' is not formatted to exactly 4 decimal places."
        )
        assert number_format.fullmatch(empirical_str), (
            f"Empirical value '{empirical_str}' is not formatted to exactly 4 decimal places."
        )

        exact_val = float(exact_str)
        empirical_val = float(empirical_str)
        assert math.isfinite(exact_val) and math.isfinite(empirical_val), 'PageRank values must be finite.'

        exact_diff = abs(exact_val - expected[i])
        assert exact_diff <= 0.0002, (
            f'Exact value for node {i} ({exact_val}) differs from the PageRank solution '
            f'({expected[i]}) by more than 0.0002.'
        )
        empirical_diff = abs(empirical_val - expected[i])
        assert empirical_diff <= 0.005, (
            f'Empirical value for node {i} ({empirical_val}) differs from the PageRank solution '
            f'({expected[i]}) by more than 0.005. MCMC might not have converged or logic is incorrect.'
        )


@pytest.fixture(scope='session', autouse=True)
def compile_submission():
    assert os.path.isfile(SOURCE), 'The source code file /home/user/pagerank.cpp does not exist.'
    completed = subprocess.run(
        ['g++', '-O3', '-I/usr/include/eigen3', 'pagerank.cpp', '-o', 'pagerank'],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f'pagerank.cpp did not compile with the instructed command. '
        f'stdout: {completed.stdout}\nstderr: {completed.stderr}'
    )


def test_01_required_files_exist():
    assert os.path.isfile(SOURCE), 'The source code file /home/user/pagerank.cpp does not exist.'
    assert os.path.isfile(RESULTS), 'The file /home/user/results.csv does not exist.'


def test_02_source_uses_eigen_decomposition():
    with open(SOURCE, errors='replace') as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<\"]Eigen(?:/|[>\"])', source), 'pagerank.cpp does not include Eigen.'
    assert re.search(
        r'(fullpivlu|partialpivlu|householderqr|colpivhouseholderqr|fullpivhouseholderqr|ldlt|llt|jacobisvd|bdcsvd|\.lu\s*\(|\.qr\s*\()',
        source,
        re.IGNORECASE,
    ), 'pagerank.cpp does not appear to use an Eigen matrix decomposition for the exact solve.'


def test_03_program_handles_derived_alternate_graph():
    run_and_check(ALTERNATE_GRAPH)


def test_04_original_graph_results():
    # Run this last so the required graph and results are left in their instructed final state.
    run_and_check(ORIGINAL_GRAPH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
