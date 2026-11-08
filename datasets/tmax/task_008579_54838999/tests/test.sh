#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_deadlock_path_json():
    file_path = "/home/user/deadlock_path.json"

    # Check if the file exists
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

    # Check if it's valid JSON and contains the correct list
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Could not read {file_path}: {e}")

    expected_path = ["T10", "T99", "T15", "T25", "T50"]

    assert isinstance(data, list), f"The JSON in {file_path} must be a list, but got {type(data).__name__}."
    assert data == expected_path, f"The shortest path is incorrect. Expected {expected_path}, but got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
