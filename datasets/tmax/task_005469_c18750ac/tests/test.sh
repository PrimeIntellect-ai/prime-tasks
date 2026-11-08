#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_deadlock_report_exists_and_correct():
    file_path = "/home/user/deadlock_report.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {file_path} is not a valid JSON.")

    assert isinstance(data, list), f"Expected the JSON root to be a list, got {type(data).__name__}."
    assert len(data) == 2, f"Expected exactly 2 deadlock cycles, found {len(data)}."

    expected_data = [
        {
            "cycle_members": ["T04", "T05", "T06"],
            "total_locked_amount": 1500.5
        },
        {
            "cycle_members": ["T01", "T02", "T03"],
            "total_locked_amount": 600.5
        }
    ]

    # Verify first item
    assert "cycle_members" in data[0], "First item missing 'cycle_members' key."
    assert "total_locked_amount" in data[0], "First item missing 'total_locked_amount' key."
    assert data[0]["cycle_members"] == expected_data[0]["cycle_members"], f"First item cycle_members mismatch. Expected {expected_data[0]['cycle_members']}, got {data[0]['cycle_members']}."
    assert data[0]["total_locked_amount"] == expected_data[0]["total_locked_amount"], f"First item total_locked_amount mismatch. Expected {expected_data[0]['total_locked_amount']}, got {data[0]['total_locked_amount']}."

    # Verify second item
    assert "cycle_members" in data[1], "Second item missing 'cycle_members' key."
    assert "total_locked_amount" in data[1], "Second item missing 'total_locked_amount' key."
    assert data[1]["cycle_members"] == expected_data[1]["cycle_members"], f"Second item cycle_members mismatch. Expected {expected_data[1]['cycle_members']}, got {data[1]['cycle_members']}."
    assert data[1]["total_locked_amount"] == expected_data[1]["total_locked_amount"], f"Second item total_locked_amount mismatch. Expected {expected_data[1]['total_locked_amount']}, got {data[1]['total_locked_amount']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
