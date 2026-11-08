#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest
from collections import deque, defaultdict

DB_PATH = "/home/user/citation_graph.db"
RESULTS_PATH = "/home/user/research_results.json"

def compute_expected_results():
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Extract clean edges: strictly ignore duplicate edges and self-citations
    cursor.execute("""
        SELECT DISTINCT source_id, target_id 
        FROM citations 
        WHERE source_id != target_id
    """)
    edges = cursor.fetchall()
    conn.close()

    in_degrees = defaultdict(int)
    graph = defaultdict(list)

    # Build graph and compute in-degrees
    for u, v in edges:
        in_degrees[v] += 1
        graph[u].append(v)

    highest_in_degree = -1
    most_cited_paper_id = -1

    # Find paper with highest in-degree (tie-breaker: lowest id)
    for node, deg in in_degrees.items():
        if deg > highest_in_degree:
            highest_in_degree = deg
            most_cited_paper_id = node
        elif deg == highest_in_degree:
            if node < most_cited_paper_id:
                most_cited_paper_id = node

    # Compute shortest directed path from 10 to 42 using BFS
    start, end = 10, 42
    queue = deque([[start]])
    visited = {start}
    shortest_path = []

    while queue:
        path = queue.popleft()
        curr = path[-1]

        if curr == end:
            shortest_path = path
            break

        # Sort neighbors to ensure deterministic BFS path if there are multiple shortest paths
        for neighbor in sorted(graph[curr]):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    return {
        "most_cited_paper_id": most_cited_paper_id,
        "highest_in_degree": highest_in_degree,
        "shortest_path_10_to_42": shortest_path
    }

def test_research_results_exist():
    assert os.path.exists(RESULTS_PATH), f"Results file not found at {RESULTS_PATH}. The pipeline must create this file."

def test_research_results_content():
    expected = compute_expected_results()

    with open(RESULTS_PATH, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    assert "most_cited_paper_id" in actual, "Missing 'most_cited_paper_id' in JSON results."
    assert "highest_in_degree" in actual, "Missing 'highest_in_degree' in JSON results."
    assert "shortest_path_10_to_42" in actual, "Missing 'shortest_path_10_to_42' in JSON results."

    assert actual["most_cited_paper_id"] == expected["most_cited_paper_id"], \
        f"Incorrect most_cited_paper_id. Expected {expected['most_cited_paper_id']}, but got {actual['most_cited_paper_id']}"

    assert actual["highest_in_degree"] == expected["highest_in_degree"], \
        f"Incorrect highest_in_degree. Expected {expected['highest_in_degree']}, but got {actual['highest_in_degree']}"

    assert actual["shortest_path_10_to_42"] == expected["shortest_path_10_to_42"], \
        f"Incorrect shortest_path_10_to_42. Expected {expected['shortest_path_10_to_42']}, but got {actual['shortest_path_10_to_42']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
