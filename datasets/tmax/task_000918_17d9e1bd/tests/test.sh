#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import math
import pytest

def test_results_json_exists_and_valid():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"Output file {results_path} was not created."
    assert os.path.isfile(results_path), f"Path {results_path} is not a file."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    assert isinstance(results, dict), "JSON root must be an object (dictionary)."

    expected_keys = {"raw_integral", "tvd_distance"}
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"Missing expected keys in JSON: {missing_keys}"

def test_results_values():
    results_path = "/home/user/results.json"
    if not os.path.exists(results_path):
        pytest.skip("Results file missing.")

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Results file is not valid JSON.")

    raw_integral = results.get("raw_integral")
    tvd_distance = results.get("tvd_distance")

    assert isinstance(raw_integral, (int, float)), f"'raw_integral' must be a number, got {type(raw_integral).__name__}."
    assert isinstance(tvd_distance, (int, float)), f"'tvd_distance' must be a number, got {type(tvd_distance).__name__}."

    # Expected values based on the specific math problem setup
    expected_raw_integral = 3.8853
    expected_tvd_distance = 0.4087

    assert math.isclose(raw_integral, expected_raw_integral, abs_tol=1e-4), \
        f"Incorrect 'raw_integral'. Expected {expected_raw_integral}, got {raw_integral}."

    assert math.isclose(tvd_distance, expected_tvd_distance, abs_tol=1e-4), \
        f"Incorrect 'tvd_distance'. Expected {expected_tvd_distance}, got {tvd_distance}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
