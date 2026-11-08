#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_deadlocks_json_exists():
    file_path = '/home/user/deadlocks.json'
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

def test_deadlocks_json_content():
    file_path = '/home/user/deadlocks.json'
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {file_path} as JSON: {e}")

    assert isinstance(data, dict), f"JSON root must be an object/dict, got {type(data).__name__}."
    assert "deadlocks" in data, "JSON object is missing the 'deadlocks' key."

    deadlocks = data["deadlocks"]
    assert isinstance(deadlocks, list), f"'deadlocks' value must be a list, got {type(deadlocks).__name__}."

    expected_deadlocks = [
        ["T1", "T2"],
        ["T3", "T4", "T5"]
    ]

    assert deadlocks == expected_deadlocks, f"Expected deadlocks to be {expected_deadlocks}, but got {deadlocks}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
