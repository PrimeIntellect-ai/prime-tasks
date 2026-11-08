#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_results_json_exists():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"{results_path} does not exist."
    assert os.path.isfile(results_path), f"{results_path} is not a file."

def test_results_json_content():
    results_path = "/home/user/results.json"
    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} is not a valid JSON file."

    expected_keys = {"sum_top_5_singular_values", "w_0", "p_value"}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, f"JSON keys do not match. Expected {expected_keys}, got {actual_keys}."

    # Expected values derived from the deterministic FASTA generation
    expected_sum = 1.22295
    expected_w0 = 0.0897
    expected_p = 3.037e-12

    actual_sum = data["sum_top_5_singular_values"]
    actual_w0 = data["w_0"]
    actual_p = data["p_value"]

    assert isinstance(actual_sum, (int, float)), "sum_top_5_singular_values must be a float."
    assert isinstance(actual_w0, (int, float)), "w_0 must be a float."
    assert isinstance(actual_p, (int, float)), "p_value must be a float."

    assert math.isclose(actual_sum, expected_sum, rel_tol=0.01), \
        f"sum_top_5_singular_values {actual_sum} is not within 1% of expected {expected_sum}."

    assert math.isclose(actual_w0, expected_w0, rel_tol=0.01), \
        f"w_0 {actual_w0} is not within 1% of expected {expected_w0}."

    assert math.isclose(actual_p, expected_p, rel_tol=0.01), \
        f"p_value {actual_p} is not within 1% of expected {expected_p}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
