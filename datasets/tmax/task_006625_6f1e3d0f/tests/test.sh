#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_resolved_hierarchy_exists_and_correct():
    path = "/home/user/resolved_hierarchy.json"
    assert os.path.isfile(path), f"Missing file: {path}"

    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} is not a valid JSON file.")

    expected_data = [
        {
            "task_id": "T1",
            "task_name": "Design",
            "dependents": [
                {
                    "task_id": "T2",
                    "task_name": "Implementation",
                    "dependents": [
                        {
                            "task_id": "T3",
                            "task_name": "Testing",
                            "dependents": [
                                {
                                    "task_id": "T4",
                                    "task_name": "Deployment",
                                    "dependents": []
                                },
                                {
                                    "task_id": "T5",
                                    "task_name": "Code Review",
                                    "dependents": []
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    ]

    assert data == expected_data, f"The contents of {path} do not match the expected resolved hierarchy."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
