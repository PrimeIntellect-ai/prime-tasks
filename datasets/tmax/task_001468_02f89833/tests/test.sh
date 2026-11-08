#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_invalid_tx_file():
    file_path = "/home/user/invalid_tx.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["T6", "T7"]
    assert lines == expected_lines, f"Expected invalid_tx.txt to contain {expected_lines}, but got {lines}."

def test_deadlocks_json_file():
    file_path = "/home/user/deadlocks.json"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."

    expected_data = [
        {
            "account1": "A1",
            "account2": "A2",
            "minute": "2023-10-01 10:05"
        }
    ]

    # Sort both lists of dicts to ensure order doesn't matter, though there's only one item here.
    def sort_key(d):
        return (d.get("account1", ""), d.get("account2", ""), d.get("minute", ""))

    sorted_data = sorted(data, key=sort_key)
    sorted_expected = sorted(expected_data, key=sort_key)

    assert sorted_data == sorted_expected, f"Expected deadlocks.json to be {expected_data}, but got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
