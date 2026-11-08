#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import pytest

def get_expected_graph():
    graph = {}

    # Read from DB
    db_path = '/home/user/dataset/papers.db'
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT source_id, target_id FROM citations_raw WHERE is_valid = 1")
        for src, tgt in c.fetchall():
            src_str = str(src)
            if src_str not in graph:
                graph[src_str] = []
            if tgt not in graph[src_str]:
                graph[src_str].append(tgt)
        conn.close()

    # Read from JSONL
    jsonl_path = '/home/user/dataset/updates.jsonl'
    if os.path.exists(jsonl_path):
        with open(jsonl_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                data = json.loads(line)
                src_str = str(data['paper_id'])
                if src_str not in graph:
                    graph[src_str] = []
                for tgt in data.get('missing_citations', []):
                    if tgt not in graph[src_str]:
                        graph[src_str].append(tgt)

    # Sort the lists
    for k in graph:
        graph[k].sort()

    return graph

def get_longest_chain(graph):
    # Convert keys to integers for processing
    int_graph = {int(k): v for k, v in graph.items()}

    memo = {}

    def dfs(node):
        if node in memo:
            return memo[node]

        max_path = [node]
        if node in int_graph:
            for neighbor in int_graph[node]:
                path = [node] + dfs(neighbor)
                if len(path) > len(max_path):
                    max_path = path
                elif len(path) == len(max_path):
                    # Tie breaking: numerically smallest starting paper ID
                    # Since we are comparing paths, we can just compare them lexicographically
                    if path < max_path:
                        max_path = path
        memo[node] = max_path
        return max_path

    # Find all nodes
    all_nodes = set(int_graph.keys())
    for v in int_graph.values():
        all_nodes.update(v)

    longest = []
    for node in sorted(all_nodes):
        path = dfs(node)
        if len(path) > len(longest):
            longest = path
        elif len(path) == len(longest):
            if path < longest:
                longest = path

    return longest

def test_graph_json_exists_and_correct():
    out_path = '/home/user/output/graph.json'
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."

    with open(out_path, 'r') as f:
        try:
            actual_graph = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {out_path} is not valid JSON.")

    expected_graph = get_expected_graph()

    assert actual_graph == expected_graph, f"Graph in {out_path} does not match the expected graph."

def test_longest_chain_json_exists_and_correct():
    out_path = '/home/user/output/longest_chain.json'
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."

    with open(out_path, 'r') as f:
        try:
            actual_chain = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {out_path} is not valid JSON.")

    expected_graph = get_expected_graph()
    expected_chain = get_longest_chain(expected_graph)

    assert actual_chain == expected_chain, f"Longest chain in {out_path} does not match the expected chain."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
