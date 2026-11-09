#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

def compute_pagerank(nodes, edges, alpha=0.85, tol=1e-6, max_iter=100):
    N = len(nodes)
    if N == 0:
        return {}

    out_degree = {n: 0 for n in nodes}
    for u, v in edges:
        out_degree[u] += 1

    pr = {n: 1.0 / N for n in nodes}
    for _ in range(max_iter):
        prev_pr = pr.copy()
        dangling_sum = sum(prev_pr[n] for n in nodes if out_degree[n] == 0)

        for n in nodes:
            pr[n] = (1.0 - alpha) / N + alpha * dangling_sum / N

        for u, v in edges:
            pr[v] += alpha * prev_pr[u] / out_degree[u]

        err = sum(abs(pr[n] - prev_pr[n]) for n in nodes)
        if err < N * tol:
            break

    return pr

def get_wcc(nodes, edges):
    adj = {n: [] for n in nodes}
    for u, v in edges:
        adj[u].append(v)
        adj[v].append(u)

    visited = set()
    components = []
    for n in nodes:
        if n not in visited:
            comp = []
            q = [n]
            visited.add(n)
            while q:
                curr = q.pop(0)
                comp.append(curr)
                for neighbor in adj[curr]:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        q.append(neighbor)
            components.append(comp)
    return components

def test_csv_exists_and_format():
    csv_path = "/home/user/top_papers.csv"
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["paper_id", "pagerank", "component_id"], "CSV header is incorrect."

        rows = list(reader)
        assert len(rows) > 0, "CSV file is empty."

        for row in rows:
            assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
            # Check pagerank format (exactly 4 decimal places)
            pr_str = row[1]
            assert "." in pr_str and len(pr_str.split(".")[1]) == 4, f"PageRank {pr_str} is not rounded to 4 decimal places."

def test_csv_correctness():
    jsonl_path = "/home/user/papers.jsonl"
    assert os.path.isfile(jsonl_path), f"Input file {jsonl_path} missing."

    valid_nodes = set()
    with open(jsonl_path, "r") as f:
        for line in f:
            if not line.strip(): continue
            data = json.loads(line)
            if data.get("year", 0) >= 2010:
                valid_nodes.add(data["paper_id"])

    edges = []
    with open(jsonl_path, "r") as f:
        for line in f:
            if not line.strip(): continue
            data = json.loads(line)
            if data["paper_id"] in valid_nodes:
                for cited in data.get("citations", []):
                    if cited in valid_nodes:
                        edges.append((data["paper_id"], cited))

    expected_pr = compute_pagerank(valid_nodes, edges)
    components = get_wcc(valid_nodes, edges)

    comp_map = {}
    for comp in components:
        comp_id = min(comp)
        for node in comp:
            comp_map[node] = comp_id

    expected_results = []
    for node in valid_nodes:
        expected_results.append({
            "paper_id": node,
            "pagerank": round(expected_pr[node], 4),
            "component_id": comp_map[node]
        })

    expected_results.sort(key=lambda x: (-x["pagerank"], x["paper_id"]))

    csv_path = "/home/user/top_papers.csv"
    actual_results = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual_results.append({
                "paper_id": row["paper_id"],
                "pagerank": float(row["pagerank"]),
                "component_id": row["component_id"]
            })

    assert len(actual_results) == len(expected_results), "Number of rows in CSV does not match the expected number of valid papers."

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert actual["paper_id"] == expected["paper_id"], f"Row {i+1} paper_id mismatch. Expected {expected['paper_id']}, got {actual['paper_id']}."
        assert actual["component_id"] == expected["component_id"], f"Row {i+1} component_id mismatch for {actual['paper_id']}."

        # Allow a tiny float difference due to potential networkx internal differences
        assert abs(actual["pagerank"] - expected["pagerank"]) <= 0.0002, f"Row {i+1} pagerank mismatch for {actual['paper_id']}. Expected ~{expected['pagerank']}, got {actual['pagerank']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
