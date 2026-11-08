#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_ab_test_results_exists():
    """Verify that the output JSON file exists."""
    file_path = "/home/user/ab_test_results.json"
    assert os.path.exists(file_path), f"The file {file_path} was not found. Ensure you saved the results to the correct location."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_ab_test_results_content():
    """Verify that the JSON file contains the correct t_statistic and p_value."""
    file_path = "/home/user/ab_test_results.json"

    assert os.path.exists(file_path), f"Missing {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert "t_statistic" in data, "The JSON file is missing the 't_statistic' key."
    assert "p_value" in data, "The JSON file is missing the 'p_value' key."

    expected_t_statistic = -3.0782
    expected_p_value = 0.0024

    actual_t_statistic = data["t_statistic"]
    actual_p_value = data["p_value"]

    assert isinstance(actual_t_statistic, (int, float)), "The 't_statistic' must be a number."
    assert isinstance(actual_p_value, (int, float)), "The 'p_value' must be a number."

    # Allow a small floating point tolerance just in case, but strict rounding was requested
    assert round(actual_t_statistic, 4) == expected_t_statistic, f"Expected t_statistic to be {expected_t_statistic}, but got {actual_t_statistic}."
    assert round(actual_p_value, 4) == expected_p_value, f"Expected p_value to be {expected_p_value}, but got {actual_p_value}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
