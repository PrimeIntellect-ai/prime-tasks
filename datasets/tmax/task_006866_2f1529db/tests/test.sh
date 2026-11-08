#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from collections import defaultdict
import pytest

def compute_expected_metrics(csv_path):
    """
    Derives the expected graph metrics directly from the raw data.
    """
    edges = defaultdict(int)
    nodes = set()

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src = row['src_ip']
            dst = row['dst_ip']
            b = int(row['bytes'])

            nodes.add(src)
            nodes.add(dst)

            # Undirected edge representation
            if src > dst:
                src, dst = dst, src
            edges[(src, dst)] += b

    # Compute Weighted Degree Centrality
    degrees = defaultdict(int)
    for (u, v), w in edges.items():
        degrees[u] += w
        degrees[v] += w

    # Sort by traffic (descending) then alphabetically (ascending)
    sorted_ips = sorted(degrees.keys(), key=lambda ip: (-degrees[ip], ip))
    top_3_ips = sorted_ips[:3]

    # Compute Connected Components
    adj = defaultdict(list)
    for (u, v) in edges.keys():
        adj[u].append(v)
        adj[v].append(u)

    visited = set()
    max_comp_size = 0

    for node in nodes:
        if node not in visited:
            # DFS to find component size
            comp_size = 0
            stack = [node]
            visited.add(node)
            while stack:
                curr = stack.pop()
                comp_size += 1
                for neighbor in adj[curr]:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        stack.append(neighbor)
            if comp_size > max_comp_size:
                max_comp_size = comp_size

    return top_3_ips, max_comp_size

def test_etl_summary_exists():
    """Test that the output JSON file has been created at the exact required path."""
    file_path = "/home/user/etl_summary.json"
    assert os.path.isfile(file_path), f"The required output file is missing: {file_path}"

def test_etl_summary_content():
    """Test that the output JSON file contains the correct structure and derived metrics."""
    json_path = "/home/user/etl_summary.json"
    csv_path = "/home/user/network_traffic.csv"

    assert os.path.isfile(json_path), f"Cannot validate content, file missing: {json_path}"
    assert os.path.isfile(csv_path), f"Source data missing, cannot compute expected metrics: {csv_path}"

    with open(json_path, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert isinstance(summary, dict), "The JSON root must be an object (dictionary)."

    assert "top_3_ips_by_traffic" in summary, "Missing key 'top_3_ips_by_traffic' in JSON."
    assert "largest_component_size" in summary, "Missing key 'largest_component_size' in JSON."

    expected_top_3, expected_max_comp_size = compute_expected_metrics(csv_path)

    actual_top_3 = summary["top_3_ips_by_traffic"]
    assert isinstance(actual_top_3, list), "'top_3_ips_by_traffic' must be a list."
    assert len(actual_top_3) == 3, f"Expected exactly 3 IPs in 'top_3_ips_by_traffic', got {len(actual_top_3)}."
    assert actual_top_3 == expected_top_3, (
        f"Incorrect top 3 IPs. Expected {expected_top_3}, but got {actual_top_3}. "
        "Ensure you are aggregating undirected edges, sorting by traffic descending, and breaking ties alphabetically."
    )

    actual_max_comp_size = summary["largest_component_size"]
    assert isinstance(actual_max_comp_size, int), "'largest_component_size' must be an integer."
    assert actual_max_comp_size == expected_max_comp_size, (
        f"Incorrect largest component size. Expected {expected_max_comp_size}, but got {actual_max_comp_size}. "
        "Ensure you are properly finding connected components in an undirected graph."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
