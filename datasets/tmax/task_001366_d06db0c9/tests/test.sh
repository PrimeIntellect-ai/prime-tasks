#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_rollup_json_exists():
    file_path = "/home/user/rollup.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The script did not generate the required output."

def test_rollup_json_content():
    file_path = "/home/user/rollup.json"

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {file_path} is not valid JSON.")

    assert isinstance(data, list), f"The root of {file_path} must be a JSON array."

    expected_data = [
        {"emp_id": 10, "total_budget": 18000},
        {"emp_id": 20, "total_budget": 14000},
        {"emp_id": 30, "total_budget": 4000},
        {"emp_id": 40, "total_budget": 14000},
        {"emp_id": 50, "total_budget": 5000},
        {"emp_id": 60, "total_budget": 7000},
        {"emp_id": 70, "total_budget": 3000}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert set(actual.keys()) == {"emp_id", "total_budget"}, f"Item at index {i} has incorrect keys. Expected exactly 'emp_id' and 'total_budget'."
        assert isinstance(actual["emp_id"], int), f"Item at index {i} has non-integer 'emp_id'."
        assert isinstance(actual["total_budget"], int), f"Item at index {i} has non-integer 'total_budget'."

        assert actual["emp_id"] == expected["emp_id"], f"Item at index {i} has incorrect emp_id. Expected {expected['emp_id']}, got {actual['emp_id']}. Make sure the output is sorted by emp_id."
        assert actual["total_budget"] == expected["total_budget"], f"Incorrect total_budget for emp_id {actual['emp_id']}. Expected {expected['total_budget']}, got {actual['total_budget']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
