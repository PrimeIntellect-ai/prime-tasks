#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_json_report_exists():
    assert os.path.isfile('/home/user/ab_test_results.json'), "/home/user/ab_test_results.json does not exist. The report was not created."

def test_json_report_content():
    report_path = '/home/user/ab_test_results.json'
    assert os.path.isfile(report_path), "Cannot check content because /home/user/ab_test_results.json does not exist."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/ab_test_results.json is not a valid JSON file."

    required_keys = ["diff", "ci_lower", "ci_upper"]
    for key in required_keys:
        assert key in data, f"Key '{key}' is missing from the JSON report."

    expected_diff = -1.5794
    expected_ci_lower = -10.5109
    expected_ci_upper = 7.3787
    tolerance = 0.0005

    assert math.isclose(data["diff"], expected_diff, abs_tol=tolerance), f"Expected 'diff' to be close to {expected_diff}, but got {data['diff']}."
    assert math.isclose(data["ci_lower"], expected_ci_lower, abs_tol=tolerance), f"Expected 'ci_lower' to be close to {expected_ci_lower}, but got {data['ci_lower']}."
    assert math.isclose(data["ci_upper"], expected_ci_upper, abs_tol=tolerance), f"Expected 'ci_upper' to be close to {expected_ci_upper}, but got {data['ci_upper']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
