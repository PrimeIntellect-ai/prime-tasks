#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def compute_pagerank(edges, alpha=0.85, max_iter=100, tol=1.0e-6):
    nodes = set()
    out_degree = {}
    for u, v in edges:
        nodes.add(u)
        nodes.add(v)

    for n in nodes:
        out_degree[n] = 0

    for u, v in edges:
        out_degree[u] += 1

    N = len(nodes)
    if N == 0:
        return {}

    pr = {n: 1.0 / N for n in nodes}

    for _ in range(max_iter):
        new_pr = {n: (1.0 - alpha) / N for n in nodes}

        # Add contributions from edges
        for u, v in edges:
            new_pr[v] += alpha * pr[u] / out_degree[u]

        # Handle dangling nodes (nodes with out_degree == 0)
        dangling_sum = sum(pr[n] for n in nodes if out_degree[n] == 0)
        if dangling_sum > 0:
            for n in nodes:
                new_pr[n] += alpha * dangling_sum / N

        # Check convergence
        err = sum(abs(new_pr[n] - pr[n]) for n in nodes)
        pr = new_pr
        if err < N * tol:
            break

    return pr

def test_pagerank_output():
    raw_data_path = "/home/user/raw_data.json"
    output_path = "/home/user/pagerank.json"

    assert os.path.exists(output_path), f"Output file missing at {output_path}"

    with open(raw_data_path, 'r') as f:
        data = json.load(f)

    edges = []
    for doc in data:
        u1 = doc["meta"]["author"]["handle"]
        for m in doc["content"]["mentions"]:
            u2 = m["u"]
            edges.append((u1, u2))

    expected_pr = compute_pagerank(edges, alpha=0.85)

    with open(output_path, 'r') as f:
        try:
            student_pr = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    assert isinstance(student_pr, dict), "PageRank output should be a JSON object (dictionary)."

    expected_nodes = set(expected_pr.keys())
    student_nodes = set(student_pr.keys())

    missing_nodes = expected_nodes - student_nodes
    extra_nodes = student_nodes - expected_nodes

    assert not missing_nodes, f"Missing nodes in PageRank output: {missing_nodes}"
    assert not extra_nodes, f"Extra nodes in PageRank output: {extra_nodes}"

    for node in expected_nodes:
        expected_val = expected_pr[node]
        student_val = student_pr[node]
        assert isinstance(student_val, (int, float)), f"PageRank value for '{node}' must be a float."
        assert math.isclose(student_val, expected_val, abs_tol=1e-4), \
            f"PageRank for '{node}' is {student_val}, expected ~{expected_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
