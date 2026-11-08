#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math

def test_model_comparison_json_exists():
    """Test that the model_comparison.json file exists."""
    json_path = '/home/user/model_comparison.json'
    assert os.path.exists(json_path), f"File {json_path} does not exist."
    assert os.path.isfile(json_path), f"Path {json_path} is not a file."

def test_model_comparison_json_content():
    """Test that the model_comparison.json contains the correct F-statistic and p-value."""
    json_path = '/home/user/model_comparison.json'
    assert os.path.exists(json_path), f"File {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not a valid JSON file."

    assert "f_stat" in data, "JSON file is missing the 'f_stat' key."
    assert "p_value" in data, "JSON file is missing the 'p_value' key."

    f_stat = data["f_stat"]
    p_value = data["p_value"]

    assert isinstance(f_stat, (int, float)), "'f_stat' must be a number."
    assert isinstance(p_value, (int, float)), "'p_value' must be a number."

    expected_f_stat = 1.2185
    expected_p_value = 0.3003

    assert math.isclose(f_stat, expected_f_stat, abs_tol=0.0002), \
        f"Expected f_stat to be close to {expected_f_stat}, but got {f_stat}"

    assert math.isclose(p_value, expected_p_value, abs_tol=0.0002), \
        f"Expected p_value to be close to {expected_p_value}, but got {p_value}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
