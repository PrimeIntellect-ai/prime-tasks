#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

def get_valid_employees(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT emp_id FROM employees")
    employees = {row[0] for row in cursor.fetchall()}
    conn.close()
    return employees

def get_valid_edges(jsonl_path, valid_employees):
    edges = []
    with open(jsonl_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            u, v = data.get("from_emp"), data.get("to_emp")
            if u in valid_employees and v in valid_employees:
                edges.append((u, v))
    return edges

def compute_pagerank(nodes, edges, alpha=0.85, max_iter=1000, tol=1.0e-6):
    n = len(nodes)
    if n == 0:
        return {}

    out_degree = {node: 0 for node in nodes}
    in_edges = {node: [] for node in nodes}
    for u, v in edges:
        out_degree[u] += 1
        in_edges[v].append(u)

    pr = {node: 1.0 / n for node in nodes}

    for _ in range(max_iter):
        new_pr = {}
        dangling_sum = sum(pr[u] for u in nodes if out_degree[u] == 0)

        diff = 0
        for node in nodes:
            s = sum(pr[u] / out_degree[u] for u in in_edges[node])
            new_pr[node] = (1 - alpha) / n + alpha * s + alpha * dangling_sum / n

        for node in nodes:
            diff += abs(new_pr[node] - pr[node])
        pr = new_pr
        if diff < tol:
            break

    return pr

def find_3_cycles(nodes, edges):
    out_edges = {node: [] for node in nodes}
    for u, v in edges:
        out_edges[u].append(v)

    cycles = []
    for u in nodes:
        for v in out_edges[u]:
            for w in out_edges[v]:
                if u in out_edges[w]:
                    cycle = [u, v, w]
                    min_idx = cycle.index(min(cycle))
                    canonical = cycle[min_idx:] + cycle[:min_idx]
                    if canonical not in cycles:
                        cycles.append(canonical)

    cycles.sort(key=lambda x: (x[0], x[1], x[2]))
    return cycles

def test_deadlock_audit_json():
    output_path = '/home/user/deadlock_audit.json'
    assert os.path.isfile(output_path), f"Output file missing at {output_path}"

    with open(output_path, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    assert "top_bottlenecks" in result, "Missing 'top_bottlenecks' in JSON output."
    assert "deadlock_cycles" in result, "Missing 'deadlock_cycles' in JSON output."

    db_path = '/home/user/employees.db'
    jsonl_path = '/home/user/delegations.jsonl'

    valid_employees = get_valid_employees(db_path)
    valid_edges = get_valid_edges(jsonl_path, valid_employees)

    nodes = list(valid_employees)
    pr = compute_pagerank(nodes, valid_edges)

    # Sort by PageRank descending, then by emp_id to break ties deterministically
    sorted_nodes = sorted(pr.keys(), key=lambda x: (-pr[x], x))
    expected_top = sorted_nodes[:3]

    expected_cycles = find_3_cycles(nodes, valid_edges)

    assert result["top_bottlenecks"] == expected_top, (
        f"Expected top bottlenecks {expected_top}, but got {result['top_bottlenecks']}."
    )

    assert result["deadlock_cycles"] == expected_cycles, (
        f"Expected deadlock cycles {expected_cycles}, but got {result['deadlock_cycles']}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
