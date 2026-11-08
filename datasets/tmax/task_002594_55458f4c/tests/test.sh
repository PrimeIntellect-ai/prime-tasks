#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_experiment_log_exists():
    assert os.path.isfile('/home/user/experiment_log.json'), (
        "The file /home/user/experiment_log.json was not found. "
        "Ensure your script outputs the final results to this exact path."
    )

def test_experiment_log_schema_and_values():
    with open('/home/user/experiment_log.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/experiment_log.json is not a valid JSON file.")

    expected_keys = {
        "top_20_mean_citations",
        "rest_mean_citations",
        "t_statistic",
        "p_value",
        "ci_lower",
        "ci_upper"
    }

    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"

    extra_keys = set(data.keys()) - expected_keys
    assert not extra_keys, f"Unexpected extra keys in JSON output: {extra_keys}"

    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f"Value for {key} must be a number."

    # Due to the strict constraints of standard library only, computing TF-IDF, TruncatedSVD, 
    # and Welch's t-test from scratch is not feasible. The values below are derived from the 
    # deterministic data generation and reference implementation provided in the prompt.
    expected_values = {
        "top_20_mean_citations": 48.6500,
        "rest_mean_citations": 30.6592,
        "t_statistic": 4.6071,
        "p_value": 0.0001,
        "ci_lower": 9.8517,
        "ci_upper": 26.1299
    }

    for key, expected_val in expected_values.items():
        actual_val = data[key]
        assert math.isclose(actual_val, expected_val, abs_tol=1e-2), (
            f"Value for {key} is {actual_val}, expected approximately {expected_val}. "
            f"Check your pipeline steps (TF-IDF params, SVD seed, retrieval logic, t-test)."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
