#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_output_file_exists():
    """Ensure the output JSON file was created."""
    assert os.path.exists("/home/user/perf_analysis.json"), "Output file /home/user/perf_analysis.json does not exist."

def test_output_json_structure_and_values():
    """Validate the contents of the output JSON file."""
    with open("/home/user/perf_analysis.json", "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/perf_analysis.json is not valid JSON.")

    expected = {
        "theoretical_mean": 0.17,
        "theoretical_variance": 0.0129,
        "mc_mean": 0.1696,
        "mc_variance": 0.0128,
        "gamma_shape": 2.2965,
        "gamma_scale": 0.0739
    }

    for key, expected_val in expected.items():
        assert key in data, f"Key '{key}' is missing from the JSON output."
        actual_val = data[key]
        assert isinstance(actual_val, (int, float)), f"Value for '{key}' must be a number."
        assert math.isclose(actual_val, expected_val, abs_tol=0.00015), \
            f"Value for '{key}' is {actual_val}, expected {expected_val} (rounded to 4 decimal places)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
