#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv

def test_deadlocks_json_exists():
    assert os.path.isfile("/home/user/deadlocks.json"), "The file /home/user/deadlocks.json was not created."

def test_deadlocks_json_content():
    csv_path = "/home/user/waits_for.csv"
    assert os.path.isfile(csv_path), "Input file is missing."

    # Parse the input CSV to derive the expected output
    edges = {}
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            waiter = int(row["waiter_id"])
            holder = int(row["holder_id"])
            time = int(row["wait_start_time"])
            edges[waiter] = (holder, time)

    # Find all cycles
    visited = set()
    cycles = []

    for start_node in edges:
        if start_node in visited:
            continue

        path = []
        current = start_node
        while current not in path:
            path.append(current)
            if current in edges:
                current = edges[current][0]
            else:
                break
        else:
            # We found a cycle
            cycle_start_idx = path.index(current)
            cycle_nodes = path[cycle_start_idx:]

            # Mark as visited
            for node in cycle_nodes:
                visited.add(node)

            # Rotate cycle to start with the smallest node
            min_node = min(cycle_nodes)
            min_idx = cycle_nodes.index(min_node)
            rotated_cycle = cycle_nodes[min_idx:] + cycle_nodes[:min_idx]

            # Find formation time
            formation_time = 0
            for i in range(len(rotated_cycle)):
                u = rotated_cycle[i]
                v = rotated_cycle[(i + 1) % len(rotated_cycle)]
                # Find edge u -> v
                edge_time = edges[u][1]
                formation_time = max(formation_time, edge_time)

            cycles.append((formation_time, rotated_cycle[0], rotated_cycle))

    # Sort cycles by formation time, then by starting process ID
    cycles.sort(key=lambda x: (x[0], x[1]))
    expected_deadlocks = [c[2] for c in cycles]

    # Read the student's output
    json_path = "/home/user/deadlocks.json"
    with open(json_path, "r") as f:
        try:
            student_deadlocks = json.load(f)
        except json.JSONDecodeError:
            assert False, "The file /home/user/deadlocks.json does not contain valid JSON."

    assert isinstance(student_deadlocks, list), "The JSON output must be a list of arrays."

    assert student_deadlocks == expected_deadlocks, (
        f"The deadlocks in the JSON file do not match the expected output or are incorrectly sorted.\n"
        f"Expected: {expected_deadlocks}\n"
        f"Got: {student_deadlocks}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
