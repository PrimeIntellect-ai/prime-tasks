#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_pipeline_results_exist_and_correct():
    """Test that pipeline_results.json is generated and contains the correct values."""
    results_path = "/home/user/pipeline_results.json"
    assert os.path.isfile(results_path), f"Expected output file {results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not a valid JSON file.")

    expected_keys = {"mean_similarity", "p_value", "ci_lower", "ci_upper"}
    assert set(results.keys()) == expected_keys, f"JSON keys do not match expected schema. Found: {list(results.keys())}"

    # Expected values derived from the ground truth script
    expected_values = {
        "mean_similarity": 0.2520,
        "p_value": 0.0000,
        "ci_lower": 0.2483,
        "ci_upper": 0.2558
    }

    for key, expected_val in expected_values.items():
        val = results[key]
        assert isinstance(val, (int, float)), f"Value for {key} must be a float."

        # Check against expected value with a small tolerance for floating point representation,
        # but since rounding to 4 decimal places is required, it should be very close.
        assert abs(val - expected_val) <= 0.0001, (
            f"Value for '{key}' is incorrect. Expected {expected_val}, got {val}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
