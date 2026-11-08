#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re

def compute_expected_results():
    # 1. Parse replication graph
    graph_path = "/home/user/replication_graph.json"
    with open(graph_path, 'r') as f:
        graph = json.load(f)

    nodes = {node['id']: node['name'] for node in graph['nodes']}
    edges = graph['edges']

    # Calculate out-degree
    out_degrees = {node_id: 0 for node_id in nodes}
    for edge in edges:
        out_degrees[edge['source']] += 1

    max_out = max(out_degrees.values())
    master_db_id = [k for k, v in out_degrees.items() if v == max_out][0]
    master_db = nodes[master_db_id]

    # Find triangular patterns
    # X -> Y, X -> Z, Y -> Z
    adj = {node_id: set() for node_id in nodes}
    for edge in edges:
        adj[edge['source']].add(edge['target'])

    triangles = []
    for x in nodes:
        for y in adj[x]:
            for z in adj[x]:
                if z in adj[y]:
                    triangles.append([nodes[x], nodes[y], nodes[z]])

    # Sort outer list
    triangles.sort(key=lambda t: (t[0], t[1], t[2]))

    # 2. Parse query plan
    plan_path = "/home/user/backup_query_plan.txt"
    with open(plan_path, 'r') as f:
        lines = f.readlines()

    max_cost = -1.0
    bottleneck_op = ""

    cost_pattern = re.compile(r'^(.*?)\(cost=[0-9.]+\.\.([0-9.]+)')
    for line in lines:
        # Remove leading "->" or whitespace
        line_clean = re.sub(r'^\s*(->\s*)?', '', line)
        match = cost_pattern.search(line_clean)
        if match:
            op_name = match.group(1).strip()
            total_cost = float(match.group(2))
            if total_cost > max_cost:
                max_cost = total_cost
                bottleneck_op = op_name

    return {
        "master_db": master_db,
        "triangular_patterns": triangles,
        "bottleneck_operation": bottleneck_op
    }

def test_backup_report_exists_and_valid():
    report_path = "/home/user/backup_report.json"
    assert os.path.exists(report_path), f"Output file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {report_path} is not valid JSON."

    assert isinstance(report, dict), f"Expected JSON object in {report_path}."

    expected_keys = {"master_db", "triangular_patterns", "bottleneck_operation"}
    assert expected_keys.issubset(report.keys()), f"Missing keys in {report_path}. Expected: {expected_keys}"

def test_backup_report_content():
    report_path = "/home/user/backup_report.json"
    if not os.path.exists(report_path):
        return # Handled by previous test

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            return

    expected = compute_expected_results()

    assert report.get("master_db") == expected["master_db"], \
        f"Incorrect master_db. Expected {expected['master_db']}, got {report.get('master_db')}."

    assert report.get("bottleneck_operation") == expected["bottleneck_operation"], \
        f"Incorrect bottleneck_operation. Expected {expected['bottleneck_operation']}, got {report.get('bottleneck_operation')}."

    actual_triangles = report.get("triangular_patterns", [])
    assert isinstance(actual_triangles, list), "triangular_patterns must be a list."

    assert len(actual_triangles) == len(expected["triangular_patterns"]), \
        f"Incorrect number of triangular patterns. Expected {len(expected['triangular_patterns'])}, got {len(actual_triangles)}."

    for i, (actual, exp) in enumerate(zip(actual_triangles, expected["triangular_patterns"])):
        assert isinstance(actual, list), f"Pattern at index {i} is not a list."
        assert len(actual) == 3, f"Pattern at index {i} does not have exactly 3 elements."
        assert actual == exp, f"Pattern at index {i} is incorrect. Expected {exp}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
