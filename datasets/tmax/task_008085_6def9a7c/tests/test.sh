#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import subprocess
from collections import defaultdict

def test_graph_etl():
    go_file = "/home/user/graph_etl.go"
    csv_file = "/home/user/raw_graph.csv"
    json_file = "/home/user/materialized_graph.json"

    assert os.path.isfile(go_file), f"Go program {go_file} does not exist."
    assert os.path.isfile(csv_file), f"Input CSV {csv_file} does not exist."

    # Run the Go program
    try:
        subprocess.run(["go", "run", go_file], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to run Go program. Error:\n{e.stderr}"

    assert os.path.isfile(json_file), f"Output JSON {json_file} was not created."

    # Compute expected output dynamically from the CSV
    nodes = set()
    edges = defaultdict(list)
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src, dst, weight = row['src'], row['dst'], int(row['weight'])
            nodes.add(src)
            nodes.add(dst)
            if weight >= 5:
                edges[src].append((dst, weight))

    expected_output = []
    for node in sorted(nodes):
        neighbors = []
        total_weight = 0
        for dst, weight in edges[node]:
            neighbors.append(dst)
            total_weight += weight
        neighbors.sort()
        expected_output.append({
            "node": node,
            "neighbors": neighbors,
            "total_weight": total_weight
        })

    # Read the actual output
    with open(json_file, 'r') as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {json_file} is not valid JSON."

    assert isinstance(actual_output, list), f"Output JSON must be an array of objects."
    assert len(actual_output) == len(expected_output), f"Expected {len(expected_output)} nodes in output, found {len(actual_output)}."

    for expected, actual in zip(expected_output, actual_output):
        assert actual.get("node") == expected["node"], f"Expected node {expected['node']}, found {actual.get('node')}."
        assert actual.get("neighbors") == expected["neighbors"], f"Expected neighbors {expected['neighbors']} for node {expected['node']}, found {actual.get('neighbors')}."
        assert actual.get("total_weight") == expected["total_weight"], f"Expected total_weight {expected['total_weight']} for node {expected['node']}, found {actual.get('total_weight')}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
