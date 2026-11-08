#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_results_file_exists():
    path = "/home/user/results.json"
    assert os.path.exists(path), f"Output file missing: {path}"
    assert os.path.isfile(path), f"Expected a file, but found a directory: {path}"

def test_results_format_and_values():
    path = "/home/user/results.json"
    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    expected_keys = {"distance", "ci_lower", "ci_upper"}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, got {actual_keys}"

    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f"Value for {key} must be a number, got {type(data[key])}"

    # Expected values derived from the exact seed and data generation process
    # distance: 2.9431
    # ci_lower: 2.8252
    # ci_upper: 3.0597
    expected_distance = 2.9431
    expected_ci_lower = 2.8252
    expected_ci_upper = 3.0597

    assert abs(data["distance"] - expected_distance) <= 0.0001, f"Expected distance to be {expected_distance}, got {data['distance']}"
    assert abs(data["ci_lower"] - expected_ci_lower) <= 0.0001, f"Expected ci_lower to be {expected_ci_lower}, got {data['ci_lower']}"
    assert abs(data["ci_upper"] - expected_ci_upper) <= 0.0001, f"Expected ci_upper to be {expected_ci_upper}, got {data['ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
