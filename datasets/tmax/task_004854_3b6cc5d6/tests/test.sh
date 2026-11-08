#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_cpp_file_exists():
    path = "/home/user/analyze_network.cpp"
    assert os.path.isfile(path), f"C++ source file {path} is missing."

def test_executable_exists():
    path = "/home/user/analyze_network"
    assert os.path.isfile(path), f"Compiled executable {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

def test_results_json_exists_and_valid():
    path = "/home/user/results.json"
    assert os.path.isfile(path), f"Results file {path} is missing."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert isinstance(data, list), f"JSON in {path} should be an array."
    assert len(data) == 3, f"Expected 3 query results, got {len(data)}."

def test_results_json_content():
    path = "/home/user/results.json"
    assert os.path.isfile(path), f"Results file {path} is missing."

    with open(path, "r") as f:
        data = json.load(f)

    expected_data = [
        {
            "query_id": "q1",
            "path": ["A", "B", "C", "D"],
            "total_transit_cost": 11,
            "total_delay_cost": 3,
            "total_cost": 14
        },
        {
            "query_id": "q2",
            "path": ["C", "D", "E"],
            "total_transit_cost": 5,
            "total_delay_cost": 3,
            "total_cost": 8
        },
        {
            "query_id": "q3",
            "path": ["A", "B", "C", "D", "E"],
            "total_transit_cost": 12,
            "total_delay_cost": 6,
            "total_cost": 18
        }
    ]

    # Sort both lists by query_id to ensure order doesn't cause false failures
    data_sorted = sorted(data, key=lambda x: x.get("query_id", ""))
    expected_sorted = sorted(expected_data, key=lambda x: x["query_id"])

    for actual, expected in zip(data_sorted, expected_sorted):
        assert actual.get("query_id") == expected["query_id"], f"Expected query_id {expected['query_id']}, got {actual.get('query_id')}"
        assert actual.get("path") == expected["path"], f"For {expected['query_id']}, expected path {expected['path']}, got {actual.get('path')}"
        assert actual.get("total_transit_cost") == expected["total_transit_cost"], f"For {expected['query_id']}, expected total_transit_cost {expected['total_transit_cost']}, got {actual.get('total_transit_cost')}"
        assert actual.get("total_delay_cost") == expected["total_delay_cost"], f"For {expected['query_id']}, expected total_delay_cost {expected['total_delay_cost']}, got {actual.get('total_delay_cost')}"
        assert actual.get("total_cost") == expected["total_cost"], f"For {expected['query_id']}, expected total_cost {expected['total_cost']}, got {actual.get('total_cost')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
