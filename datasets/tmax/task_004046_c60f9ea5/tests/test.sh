#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

JSON_PATH = "/home/user/eng_top_mgr_hierarchy.json"

def test_json_file_exists():
    assert os.path.exists(JSON_PATH), f"Expected JSON file at {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"Path {JSON_PATH} is not a file."

def test_json_content():
    assert os.path.exists(JSON_PATH), f"Expected JSON file at {JSON_PATH} does not exist."

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON file {JSON_PATH}. Invalid JSON format: {e}")

    assert "target_employee" in data, "Missing 'target_employee' key in the JSON file."
    assert data["target_employee"] == "Bob", f"Expected 'target_employee' to be 'Bob', but got '{data['target_employee']}'."

    assert "department" in data, "Missing 'department' key in the JSON file."
    assert data["department"] == "Engineering", f"Expected 'department' to be 'Engineering', but got '{data['department']}'."

    assert "descendant_count" in data, "Missing 'descendant_count' key in the JSON file."
    assert data["descendant_count"] == 6, f"Expected 'descendant_count' to be 6, but got {data['descendant_count']}."

    assert "chain_to_ceo" in data, "Missing 'chain_to_ceo' key in the JSON file."
    expected_chain = ["Alice", "Bob"]
    assert data["chain_to_ceo"] == expected_chain, f"Expected 'chain_to_ceo' to be {expected_chain}, but got {data['chain_to_ceo']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
