#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_deadlocks_json_exists():
    path = "/home/user/deadlocks.json"
    assert os.path.isfile(path), f"File {path} does not exist."

def test_deadlocks_json_content():
    path = "/home/user/deadlocks.json"
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not a valid JSON file.")

    expected = [
        ["T1", "T2", "T3"],
        ["T1", "T4"],
        ["T7", "T8", "T9"]
    ]

    assert data == expected, f"Content of {path} is incorrect. Expected {expected}, but got {data}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
