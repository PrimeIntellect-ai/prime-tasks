#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import math

def test_result_json_exists():
    """Test that the result.json file exists."""
    result_path = "/home/user/result.json"
    assert os.path.exists(result_path), f"Output file {result_path} does not exist."
    assert os.path.isfile(result_path), f"Path {result_path} is not a file."

def test_result_json_content():
    """Test that result.json has the correct dominant frequency and peak power."""
    result_path = "/home/user/result.json"

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} does not contain valid JSON.")

    assert "dominant_frequency" in data, "Key 'dominant_frequency' is missing from result.json."
    assert "peak_power" in data, "Key 'peak_power' is missing from result.json."

    expected_freq = 0.3333
    expected_power = 62.4868

    actual_freq = data["dominant_frequency"]
    actual_power = data["peak_power"]

    assert isinstance(actual_freq, (int, float)), "'dominant_frequency' must be a number."
    assert isinstance(actual_power, (int, float)), "'peak_power' must be a number."

    assert math.isclose(actual_freq, expected_freq, abs_tol=1e-4), \
        f"Expected dominant_frequency to be {expected_freq}, but got {actual_freq}."

    assert math.isclose(actual_power, expected_power, abs_tol=1e-4), \
        f"Expected peak_power to be {expected_power}, but got {actual_power}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
