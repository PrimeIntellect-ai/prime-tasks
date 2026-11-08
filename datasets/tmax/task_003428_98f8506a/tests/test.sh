#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import random
import subprocess
from collections import deque
import pytest

SOURCE_PATH = '/home/user/model_fit.c'
RESULTS_PATH = '/home/user/fit_results.txt'
EDGELIST_PATH = '/home/user/molecule.edgelist'
BINARY_PATH = '/tmp/model_fit_verifier_bin'

def get_expected_results():
    edgelist_path = '/home/user/molecule.edgelist'
    assert os.path.exists(edgelist_path), f"Missing {edgelist_path}"

    adj = {}
    max_node = 0
    with open(edgelist_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            u, v = map(int, line.split())
            if u not in adj: adj[u] = []
            if v not in adj: adj[v] = []
            adj[u].append(v)
            adj[v].append(u)
            max_node = max(max_node, u, v)

    N = max_node + 1

    lengths = {}
    D = 0
    counts = {}
    total_pairs = 0

    for start in range(N):
        q = deque([start])
        dist = {start: 0}
        while q:
            u = q.popleft()
            for v in adj.get(u, []):
                if v not in dist:
                    dist[v] = dist[u] + 1
                    q.append(v)

        for v, d in dist.items():
            if start < v:
                counts[d] = counts.get(d, 0) + 1
                if d > D:
                    D = d
                total_pairs += 1

    emp = {d: counts.get(d, 0) / total_pairs for d in range(1, D + 1)}

    def T(d):
        return (3**d) / math.factorial(d)

    sum_T = sum(T(d) for d in range(1, D + 1))
    theory = {d: T(d) / sum_T for d in range(1, D + 1)}

    tvd = 0.5 * sum(abs(emp.get(d, 0) - theory[d]) for d in range(1, D + 1))

    return D, tvd

def assert_current_result():
    expected_D, expected_tvd = get_expected_results()
    assert os.path.exists(RESULTS_PATH), f"Program did not create {RESULTS_PATH}"
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."
    with open(RESULTS_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {RESULTS_PATH}, found {len(lines)}"
    assert lines[0] == f"Diameter: {expected_D}"
    assert lines[1] == f"TVD: {expected_tvd:.4f}"

def run_submission():
    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        [BINARY_PATH], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert_current_result()

def write_graph(n, edges):
    ordered = list(edges)
    random.SystemRandom().shuffle(ordered)
    with open(EDGELIST_PATH, 'w') as f:
        for u, v in ordered:
            f.write(f"{u} {v}\n")

def test_model_fit_source_exists_and_compiles():
    assert os.path.exists(SOURCE_PATH), f"Missing required C source file {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file"
    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)
    completed = subprocess.run(
        ['gcc', SOURCE_PATH, '-o', BINARY_PATH, '-lm'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, f"C source failed to compile: {completed.stderr}"
    assert os.path.isfile(BINARY_PATH), "Compiler did not produce an executable"

def test_compiled_program_computes_results():
    assert os.path.isfile(BINARY_PATH), "Compiled submission is missing"
    with open(EDGELIST_PATH, 'rb') as f:
        original_graph = f.read()

    rng = random.SystemRandom()
    try:
        for n, probability in ((13, 0.16), (21, 0.24)):
            edges = {(i, i + 1) for i in range(n - 1)}
            for u in range(n):
                for v in range(u + 2, n):
                    if rng.random() < probability:
                        edges.add((u, v))
            write_graph(n, edges)
            run_submission()
    finally:
        with open(EDGELIST_PATH, 'wb') as f:
            f.write(original_graph)

    run_submission()

def test_fit_results_exists():
    results_path = '/home/user/fit_results.txt'
    assert os.path.exists(results_path), f"File {results_path} does not exist."
    assert os.path.isfile(results_path), f"{results_path} is not a file."

def test_fit_results_content():
    results_path = '/home/user/fit_results.txt'
    assert os.path.exists(results_path), f"File {results_path} does not exist."

    expected_D, expected_tvd = get_expected_results()

    with open(results_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {results_path}, found {len(lines)}"

    expected_line1 = f"Diameter: {expected_D}"
    expected_line2 = f"TVD: {expected_tvd:.4f}"

    assert lines[0] == expected_line1, f"First line mismatch. Expected '{expected_line1}', got '{lines[0]}'"
    assert lines[1] == expected_line2, f"Second line mismatch. Expected '{expected_line2}', got '{lines[1]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
