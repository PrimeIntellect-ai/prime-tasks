#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_results_json_exists_and_correct():
    """Check that results.json exists and contains the correct bootstrap results."""
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"The results file {results_path} is missing."
    assert os.path.isfile(results_path), f"The path {results_path} is not a file."

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {results_path} is not valid JSON."

    expected_keys = {"beta_opt", "beta_lower", "beta_upper"}
    assert set(results.keys()) == expected_keys, f"The JSON keys must be exactly {expected_keys}, but got {set(results.keys())}."

    # Expected values derived from the canonical solution
    expected_beta_opt = 0.4901375549005953
    expected_beta_lower = 0.46823340632646274
    expected_beta_upper = 0.5186008630730704

    tolerance = 1e-5

    assert math.isclose(results["beta_opt"], expected_beta_opt, rel_tol=tolerance, abs_tol=tolerance), \
        f"beta_opt is {results['beta_opt']}, expected approx {expected_beta_opt}."

    assert math.isclose(results["beta_lower"], expected_beta_lower, rel_tol=tolerance, abs_tol=tolerance), \
        f"beta_lower is {results['beta_lower']}, expected approx {expected_beta_lower}."

    assert math.isclose(results["beta_upper"], expected_beta_upper, rel_tol=tolerance, abs_tol=tolerance), \
        f"beta_upper is {results['beta_upper']}, expected approx {expected_beta_upper}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
