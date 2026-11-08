#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_analysis_results_exists():
    file_path = "/home/user/analysis_results.json"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_analysis_results_content():
    file_path = "/home/user/analysis_results.json"
    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{file_path} is not a valid JSON file."

    assert "dominant_error_frequency_hz" in data, "Key 'dominant_error_frequency_hz' is missing from the JSON."
    assert "growth_rate_b" in data, "Key 'growth_rate_b' is missing from the JSON."

    freq = data["dominant_error_frequency_hz"]
    growth = data["growth_rate_b"]

    assert isinstance(freq, (int, float)), "dominant_error_frequency_hz must be a number."
    assert isinstance(growth, (int, float)), "growth_rate_b must be a number."

    assert math.isclose(freq, 25.0, abs_tol=0.1), f"Expected dominant_error_frequency_hz to be 25.0, but got {freq}"
    assert math.isclose(growth, 0.5, abs_tol=0.1), f"Expected growth_rate_b to be 0.5, but got {growth}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
