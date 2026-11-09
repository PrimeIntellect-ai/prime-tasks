#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_org_report_exists():
    file_path = "/home/user/org_report.json"
    assert os.path.exists(file_path), f"Expected file {file_path} was not created."
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."

def test_org_report_content():
    file_path = "/home/user/org_report.json"
    assert os.path.exists(file_path), f"Expected file {file_path} was not created."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    # Check top-level keys
    assert data.get("manager_id") == 2, f"Expected manager_id to be 2, got {data.get('manager_id')}"
    assert data.get("total_subordinate_salary") == 470000, f"Expected total_subordinate_salary to be 470000, got {data.get('total_subordinate_salary')}"
    assert data.get("page") == 2, f"Expected page to be 2, got {data.get('page')}"
    assert data.get("page_size") == 2, f"Expected page_size to be 2, got {data.get('page_size')}"

    # Check subordinates list
    subordinates = data.get("subordinates")
    assert isinstance(subordinates, list), "Expected 'subordinates' to be a list."
    assert len(subordinates) == 2, f"Expected 2 subordinates on page 2, got {len(subordinates)}."

    # Check the exact contents of the subordinates list
    expected_subordinates = [
        {
            "emp_id": 10,
            "name": "Judy",
            "salary": 95000
        },
        {
            "emp_id": 9,
            "name": "Ivan",
            "salary": 85000
        }
    ]

    assert subordinates == expected_subordinates, f"Subordinates list does not match expected. Got: {subordinates}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
