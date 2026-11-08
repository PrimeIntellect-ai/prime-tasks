#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re

import numpy as np
import pandas as pd
import pytest


def test_pagerank_mse_and_format():
    # 1. Compute ground truth using numpy.
    edges = [
        ("Alice", "Bob", 2),
        ("Bob", "Charlie", 3),
        ("Alice", "Dave", 1),
        ("Dave", "Charlie", 2),
        ("Charlie", "Alice", 4),
        ("Dave", "Eve", 2),
        ("Eve", "Charlie", 5),
    ]

    edge_weights = {}
    for u, v, w in edges:
        edge_weights[(u, v)] = edge_weights.get((u, v), 0) + w

    nodes = sorted(set(
        [u for u, v in edge_weights.keys()] +
        [v for u, v in edge_weights.keys()]
    ))
    node_to_idx = {node: i for i, node in enumerate(nodes)}
    n = len(nodes)

    A = np.zeros((n, n))
    for (u, v), w in edge_weights.items():
        A[node_to_idx[u], node_to_idx[v]] = w

    out_sums = A.sum(axis=1)
    M = np.zeros((n, n))
    for i in range(n):
        if out_sums[i] > 0:
            M[i, :] = A[i, :] / out_sums[i]
        else:
            M[i, :] = 1.0 / n

    alpha = 0.85
    pr = np.ones(n) / n
    for _ in range(100):
        pr = alpha * np.dot(M.T, pr) + (1 - alpha) / n

    truth_pr = {nodes[i]: pr[i] for i in range(n)}

    # 2. Read and validate the agent's output.
    agent_file = "/home/user/pagerank_results.csv"
    assert os.path.exists(agent_file), f"Agent's output file not found at {agent_file}"
    assert os.path.isfile(agent_file), "Agent output must be a regular CSV file"

    try:
        with open(agent_file, "r", newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))
    except Exception as e:
        pytest.fail(f"Could not read agent's output file: {e}")

    assert rows, "CSV is empty"
    assert rows[0] == ["node", "pagerank_score"], \
        "CSV must have exactly two columns in this order: node,pagerank_score"
    assert all(len(row) == 2 for row in rows), "Every CSV row must have exactly two columns"

    data_rows = rows[1:]
    expected_nodes = set(truth_pr)
    submitted_nodes = [row[0] for row in data_rows]
    assert len(submitted_nodes) == len(expected_nodes), \
        "CSV must contain exactly one row for every graph node"
    assert len(set(submitted_nodes)) == len(submitted_nodes), "CSV contains duplicate nodes"
    assert set(submitted_nodes) == expected_nodes, \
        "CSV node coverage must exactly match the graph nodes"

    score_pattern = re.compile(r"^(?:0|[1-9][0-9]*)\.[0-9]{6}$")
    parsed_rows = []
    for node, score_text in data_rows:
        assert score_pattern.fullmatch(score_text), \
            f"PageRank score for {node} must be formatted to exactly 6 decimal places"
        score = float(score_text)
        assert math.isfinite(score), f"PageRank score for {node} must be finite"
        parsed_rows.append((node, score))

    expected_order = sorted(parsed_rows, key=lambda item: (-item[1], item[0]))
    assert parsed_rows == expected_order, \
        "Rows must be sorted by descending pagerank_score, with node alphabetically for ties"

    try:
        df_agent = pd.read_csv(agent_file)
        assert 'node' in df_agent.columns and 'pagerank_score' in df_agent.columns, \
            "CSV must contain 'node' and 'pagerank_score' columns"
        assert list(df_agent.columns) == ['node', 'pagerank_score'], \
            "CSV must contain exactly the required two columns"
        agent_pr = dict(zip(df_agent['node'], df_agent['pagerank_score']))
    except Exception as e:
        pytest.fail(f"Could not read or parse agent's output file: {e}")

    # 3. Calculate MSE over the fixed required node set only.
    mse_sum = 0.0
    for node in nodes:
        t_val = truth_pr[node]
        try:
            a_val = float(agent_pr[node])
        except (ValueError, TypeError, KeyError):
            a_val = 0.0
        mse_sum += (t_val - a_val) ** 2

    mse = mse_sum / n

    # 4. Assert against the original threshold.
    threshold = 0.00001
    assert mse < threshold, f"MSE {mse:.8f} is not strictly less than {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
