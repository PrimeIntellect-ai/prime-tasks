#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_result_file_exists_and_correct():
    """Test that the result file exists and contains the correct entity name."""
    result_path = '/home/user/result.txt'
    entities_path = '/home/user/entities.csv'
    connections_path = '/home/user/connections.csv'

    assert os.path.isfile(result_path), f"Missing file: {result_path}"

    with open(result_path, 'r') as f:
        ans = f.read().strip()

    assert ans != "", "Result file is empty."

    # Parse entities to find CORE nodes
    core_nodes = {}
    if os.path.isfile(entities_path):
        with open(entities_path, 'r') as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) >= 3 and row[0] == 'CORE':
                    try:
                        node_id = int(row[1])
                        node_name = row[2]
                        core_nodes[node_id] = node_name
                    except ValueError:
                        pass

    # Note: NetworkX PageRank of the deterministic setup yields node 6 as the highest.
    # While we could re-implement the full PageRank power iteration in pure Python, 
    # checking against the known deterministic top node name ensures exact correctness.
    expected_name = "Entity_Name_6_CORE"

    assert ans == expected_name, f"Incorrect entity name in result.txt. Expected '{expected_name}', got '{ans}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
