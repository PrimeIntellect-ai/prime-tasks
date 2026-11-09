#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_analyzed_nodes_json_exists():
    output_path = '/home/user/analyzed_nodes.json'
    assert os.path.isfile(output_path), f"Output file {output_path} is missing. The task requires creating this file."

def test_analyzed_nodes_json_matches_truth():
    output_path = '/home/user/analyzed_nodes.json'
    truth_path = '/tests/.truth.json'

    assert os.path.isfile(output_path), f"Output file {output_path} is missing."
    assert os.path.isfile(truth_path), f"Ground truth file {truth_path} is missing."

    with open(output_path, 'r') as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {output_path} is not valid JSON."

    with open(truth_path, 'r') as f:
        truth_data = json.load(f)

    assert isinstance(output_data, list), "Output must be a JSON array of objects."
    assert len(output_data) == len(truth_data), f"Expected {len(truth_data)} nodes in output, found {len(output_data)}."

    # Validate sorting
    nodes_in_output = [item.get("node") for item in output_data]
    assert nodes_in_output == sorted(nodes_in_output), "Output JSON array is not sorted alphabetically by the 'node' field."

    # Validate contents
    for i, (out_item, truth_item) in enumerate(zip(output_data, truth_data)):
        assert out_item.get("node") == truth_item["node"], f"Node mismatch at index {i}: expected {truth_item['node']}, got {out_item.get('node')}."

        out_avg = out_item.get("max_rolling_3_avg")
        truth_avg = truth_item["max_rolling_3_avg"]
        assert out_avg is not None, f"Missing 'max_rolling_3_avg' for node {truth_item['node']}."
        assert isinstance(out_avg, (int, float)), f"'max_rolling_3_avg' for node {truth_item['node']} must be a number."
        assert abs(out_avg - truth_avg) <= 1e-4, f"max_rolling_3_avg mismatch for node {truth_item['node']}: expected {truth_avg}, got {out_avg}."

        out_pr = out_item.get("pagerank")
        truth_pr = truth_item["pagerank"]
        assert out_pr is not None, f"Missing 'pagerank' for node {truth_item['node']}."
        assert isinstance(out_pr, (int, float)), f"'pagerank' for node {truth_item['node']} must be a number."
        assert abs(out_pr - truth_pr) <= 1e-4, f"pagerank mismatch for node {truth_item['node']}: expected {truth_pr}, got {out_pr}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
