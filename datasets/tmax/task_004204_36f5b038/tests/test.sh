#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_director_budgets_json_exists():
    """Check if the output JSON file exists."""
    file_path = "/home/user/director_budgets.json"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

def test_director_budgets_json_content():
    """Verify the contents of the output JSON file."""
    file_path = "/home/user/director_budgets.json"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    expected_data = {
        "Alice": 240,
        "David": 120,
        "Frank": 270
    }

    assert isinstance(data, dict), f"The JSON root must be a dictionary, got {type(data).__name__}."

    assert data == expected_data, (
        f"The calculated budgets do not match the expected values.\n"
        f"Expected: {expected_data}\n"
        f"Actual: {data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
