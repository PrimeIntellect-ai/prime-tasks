#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv

def test_cross_region_edges_csv():
    json_path = "/home/user/backup_metadata.json"
    csv_path = "/home/user/cross_region_edges.csv"

    assert os.path.isfile(json_path), f"Input file {json_path} is missing."
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    with open(json_path, 'r') as f:
        nodes = json.load(f)

    regions = {}
    graph = {}

    for node in nodes:
        node_id = node.get("node_id")
        regions[node_id] = node.get("region")
        graph[node_id] = []

    for node in nodes:
        node_id = node.get("node_id")
        replicates_from = node.get("replicates_from")
        if replicates_from:
            if replicates_from not in graph:
                graph[replicates_from] = []
            graph[replicates_from].append(node_id)

    # Traverse from master-eu-central-01
    root = "master-eu-central-01"
    expected_edges = []

    def traverse(current):
        for child in graph.get(current, []):
            if regions[current] != regions[child]:
                expected_edges.append({
                    "source_id": current,
                    "target_id": child,
                    "source_region": regions[current],
                    "target_region": regions[child]
                })
            traverse(child)

    if root in graph:
        traverse(root)

    expected_edges.sort(key=lambda x: (x["source_id"], x["target_id"]))

    actual_edges = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["source_id", "target_id", "source_region", "target_region"], \
            f"CSV headers do not match the expected headers. Got: {reader.fieldnames}"
        for row in reader:
            actual_edges.append(row)

    assert len(actual_edges) == len(expected_edges), \
        f"Expected {len(expected_edges)} cross-region edges, but found {len(actual_edges)}."

    for i, (actual, expected) in enumerate(zip(actual_edges, expected_edges)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
