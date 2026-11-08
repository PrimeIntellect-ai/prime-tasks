#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_graph_results_exists():
    assert os.path.isfile("/home/user/graph_results.json"), "The file /home/user/graph_results.json does not exist."

def test_graph_results_content():
    file_path = "/home/user/graph_results.json"
    with open(file_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} is not a valid JSON file.")

    assert "top_5_pagerank" in results, "Missing 'top_5_pagerank' key in the output JSON."
    assert "top_3_community_sizes" in results, "Missing 'top_3_community_sizes' key in the output JSON."

    # Expected values based on the provided dataset and algorithms
    expected_top_5 = ['P01', 'P08', 'P02', 'P05', 'P06']
    expected_sizes = [4, 3, 3]

    actual_top_5 = results["top_5_pagerank"]
    actual_sizes = results["top_3_community_sizes"]

    assert actual_top_5 == expected_top_5, f"Expected top_5_pagerank to be {expected_top_5}, got {actual_top_5}"
    assert actual_sizes == expected_sizes, f"Expected top_3_community_sizes to be {expected_sizes}, got {actual_sizes}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
