#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_optimization_report():
    json_path = "/home/user/query_plan.json"
    report_path = "/home/user/optimization_report.txt"

    assert os.path.exists(json_path), f"The file {json_path} does not exist."
    assert os.path.exists(report_path), f"The file {report_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} is not valid JSON.")

    nodes = data.get("nodes", [])
    edges = data.get("edges", [])

    # Calculate out-degrees
    out_degrees = {}
    for edge in edges:
        source = edge.get("source")
        if source:
            out_degrees[source] = out_degrees.get(source, 0) + 1

    if not out_degrees:
        pytest.fail("No edges found in the graph.")

    # Find the node with the highest out-degree, tie-break alphabetically
    max_out_degree = max(out_degrees.values())
    candidates = [node for node, degree in out_degrees.items() if degree == max_out_degree]
    candidates.sort()
    bottleneck_node_id = candidates[0]

    # Find the type of the bottleneck node
    bottleneck_type = None
    for node in nodes:
        if node.get("id") == bottleneck_node_id:
            bottleneck_type = node.get("type")
            break

    assert bottleneck_type is not None, f"Node {bottleneck_node_id} not found in nodes array."

    # Calculate total cost for all nodes of this type
    total_cost = sum(node.get("cost", 0) for node in nodes if node.get("type") == bottleneck_type)

    expected_output = f"Bottleneck_Type: {bottleneck_type} | Total_Cost: {total_cost}"

    with open(report_path, 'r') as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output, (
        f"File {report_path} content is incorrect.\n"
        f"Expected: '{expected_output}'\n"
        f"Actual: '{actual_output.strip()}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
