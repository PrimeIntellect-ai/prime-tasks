#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def compute_expected_pagerank():
    # Pure Python implementation of NetworkX PageRank for the specific graph
    nodes = [101, 102, 103, 104, 105]
    names = {
        101: "Alice Smith",
        102: "Bob Jones",
        103: "Charlie Brown",
        104: "Diana Prince",
        105: "Evan Wright"
    }

    edges = [
        (101, 103, 750),
        (101, 104, 1500),
        (102, 101, 200),
        (103, 104, 800),
        (105, 104, 3000),
        (104, 101, 100),
        (105, 101, 400)
    ]

    out_weights = {n: 0.0 for n in nodes}
    for u, v, w in edges:
        out_weights[u] += w

    pr = {n: 1.0 / len(nodes) for n in nodes}
    alpha = 0.85

    # Power iteration
    for _ in range(100):
        new_pr = {n: (1.0 - alpha) / len(nodes) for n in nodes}
        for u, v, w in edges:
            if out_weights[u] > 0:
                new_pr[v] += alpha * pr[u] * (w / out_weights[u])
        pr = new_pr

    results = []
    for emp_id, score in pr.items():
        results.append({
            "employee_id": emp_id,
            "name": names[emp_id],
            "pagerank": score
        })

    results.sort(key=lambda x: x['pagerank'], reverse=True)
    return results[:3]

def test_top_influencers_json_exists():
    """Test that the output JSON file exists."""
    file_path = "/home/user/top_influencers.json"
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist. Did you export the results?"

def test_top_influencers_json_format_and_values():
    """Test that the output JSON matches the expected top 3 influencers and PageRank scores."""
    file_path = "/home/user/top_influencers.json"

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of objects."
    assert len(data) == 3, f"Expected exactly 3 employees in the output, but found {len(data)}."

    expected_top_3 = compute_expected_pagerank()

    for i, (actual, expected) in enumerate(zip(data, expected_top_3)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."

        # Check keys
        expected_keys = {"employee_id", "name", "pagerank"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        # Check values
        assert actual["employee_id"] == expected["employee_id"], f"Rank {i+1} employee_id mismatch. Expected {expected['employee_id']}, got {actual['employee_id']}."
        assert actual["name"] == expected["name"], f"Rank {i+1} name mismatch. Expected '{expected['name']}', got '{actual['name']}'."

        # Check pagerank with tolerance
        assert isinstance(actual["pagerank"], (int, float)), f"Rank {i+1} pagerank must be a float."
        assert abs(actual["pagerank"] - expected["pagerank"]) < 1e-4, \
            f"Rank {i+1} pagerank mismatch. Expected {expected['pagerank']:.5f}, got {actual['pagerank']:.5f}."

def test_top_influencers_sorted_correctly():
    """Ensure the JSON array is sorted in descending order by PageRank."""
    file_path = "/home/user/top_influencers.json"
    with open(file_path, 'r') as f:
        data = json.load(f)

    scores = [item['pagerank'] for item in data if 'pagerank' in item]
    assert scores == sorted(scores, reverse=True), "The output JSON array is not sorted in descending order by PageRank."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
