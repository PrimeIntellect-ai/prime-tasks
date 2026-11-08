#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_analysis_results_exists():
    """Test that the analysis_results.json file exists in the correct location."""
    file_path = "/home/user/analysis_results.json"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

def test_analysis_results_content():
    """Test that the analysis_results.json contains the correct metrics."""
    file_path = "/home/user/analysis_results.json"

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    # Check for required keys
    assert "abs_correlation" in data, "Key 'abs_correlation' is missing from the JSON output."
    assert "ttest_p_value" in data, "Key 'ttest_p_value' is missing from the JSON output."

    # Check types
    assert isinstance(data["abs_correlation"], (int, float)), "'abs_correlation' must be a numeric value."
    assert isinstance(data["ttest_p_value"], (int, float)), "'ttest_p_value' must be a numeric value."

    # Validate values with tolerance for floating point variations
    expected_correlation = 0.2198
    actual_correlation = data["abs_correlation"]
    assert abs(actual_correlation - expected_correlation) <= 0.0002, (
        f"Expected 'abs_correlation' to be approximately {expected_correlation}, "
        f"but got {actual_correlation}."
    )

    expected_p_value = 0.0
    actual_p_value = data["ttest_p_value"]
    assert abs(actual_p_value - expected_p_value) <= 0.0001, (
        f"Expected 'ttest_p_value' to be approximately {expected_p_value}, "
        f"but got {actual_p_value}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
