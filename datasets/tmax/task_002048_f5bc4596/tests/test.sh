#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest
from collections import defaultdict, deque

def get_graph():
    transactions_file = "/home/user/data/transactions.csv"
    graph = defaultdict(list)
    nodes = set()
    if os.path.exists(transactions_file):
        with open(transactions_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                u = row['source_id']
                v = row['target_id']
                graph[u].append(v)
                nodes.add(u)
                nodes.add(v)
    return graph, nodes

def find_simple_cycles(graph):
    # Simple DFS to find cycles of length 3 and 4
    cycles = []
    def dfs(start_node, current_node, path):
        if len(path) > 4:
            return
        for neighbor in graph[current_node]:
            if neighbor == start_node and len(path) >= 3:
                # Found a cycle
                cycles.append(path)
            elif neighbor not in path:
                dfs(start_node, neighbor, path + [neighbor])

    for node in graph:
        dfs(node, node, [node])

    # Deduplicate cycles (since [A,B,C] and [B,C,A] are the same)
    unique_cycles = set()
    for c in cycles:
        min_idx = c.index(min(c))
        canon = tuple(c[min_idx:] + c[:min_idx])
        unique_cycles.add(canon)

    return unique_cycles

def brandes_betweenness(graph, nodes):
    cb = {v: 0.0 for v in nodes}
    for s in nodes:
        S = []
        P = defaultdict(list)
        sigma = {v: 0 for v in nodes}
        sigma[s] = 1
        d = {v: -1 for v in nodes}
        d[s] = 0
        Q = deque([s])

        while Q:
            v = Q.popleft()
            S.append(v)
            for w in graph[v]:
                if d[w] < 0:
                    Q.append(w)
                    d[w] = d[v] + 1
                if d[w] == d[v] + 1:
                    sigma[w] += sigma[v]
                    P[w].append(v)

        delta = {v: 0.0 for v in nodes}
        while S:
            w = S.pop()
            for v in P[w]:
                delta[v] += (sigma[v] / sigma[w]) * (1 + delta[w])
            if w != s:
                cb[w] += delta[w]

    # Normalize for directed graph: divide by (N-1)(N-2)
    n = len(nodes)
    if n > 2:
        norm = (n - 1) * (n - 2)
        for v in cb:
            cb[v] /= norm

    return cb

def test_json_file_exists():
    assert os.path.isfile("/home/user/cycle_centrality.json"), "Output file /home/user/cycle_centrality.json does not exist."

def test_json_structure_and_values():
    output_file = "/home/user/cycle_centrality.json"
    assert os.path.isfile(output_file), "Output file is missing."

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    assert isinstance(data, list), "Output JSON must be a list of dictionaries."
    assert len(data) == 3, f"Expected exactly 3 items in the output, found {len(data)}."

    graph, nodes = get_graph()
    cycles = find_simple_cycles(graph)

    cycle_nodes = set()
    for c in cycles:
        cycle_nodes.update(c)

    bc = brandes_betweenness(graph, nodes)

    expected_results = []
    for node in cycle_nodes:
        expected_results.append({
            "entity_id": node,
            "centrality": round(bc[node], 4)
        })

    expected_results.sort(key=lambda x: (-x['centrality'], x['entity_id']))
    expected_top_3 = expected_results[:3]

    for i in range(3):
        assert isinstance(data[i], dict), f"Item at index {i} is not a dictionary."
        assert "entity_id" in data[i], f"Item at index {i} is missing 'entity_id'."
        assert "centrality" in data[i], f"Item at index {i} is missing 'centrality'."

        assert data[i]["entity_id"] == expected_top_3[i]["entity_id"], f"Rank {i+1} entity_id mismatch. Expected {expected_top_3[i]['entity_id']}, got {data[i]['entity_id']}."
        assert data[i]["centrality"] == expected_top_3[i]["centrality"], f"Rank {i+1} centrality mismatch for {data[i]['entity_id']}. Expected {expected_top_3[i]['centrality']}, got {data[i]['centrality']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
