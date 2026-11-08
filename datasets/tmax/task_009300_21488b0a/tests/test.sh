#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_system_audit_json():
    """Test that the system_audit.json file exists, is valid JSON, and contains the correct sorted data."""
    file_path = "/home/user/system_audit.json"

    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    try:
        with open(file_path, "r") as f:
            actual_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_data = [
        {
            "system": "http://example.org/audit#SystemC",
            "user_count": 5
        },
        {
            "system": "http://example.org/audit#SystemA",
            "user_count": 3
        },
        {
            "system": "http://example.org/audit#SystemB",
            "user_count": 2
        },
        {
            "system": "http://example.org/audit#SystemD",
            "user_count": 1
        },
        {
            "system": "http://example.org/audit#SystemE",
            "user_count": 1
        }
    ]

    assert isinstance(actual_data, list), "The JSON output must be a list of objects."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} items, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Item at index {i} does not match expected. Expected: {expected}, Actual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
