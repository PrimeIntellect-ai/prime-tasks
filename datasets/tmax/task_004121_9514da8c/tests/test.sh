#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_results_json():
    result_path = '/home/user/results.json'
    assert os.path.isfile(result_path), f"File {result_path} does not exist."

    with open(result_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {result_path} is not valid JSON."

    expected_keys = ["valid_count", "median_sigma1_ci_lower", "median_sigma1_ci_upper"]
    for key in expected_keys:
        assert key in results, f"Key '{key}' is missing from results.json."

    assert results["valid_count"] == 85, f"Expected valid_count to be 85, got {results['valid_count']}."
    assert results["median_sigma1_ci_lower"] == 13.9042, f"Expected median_sigma1_ci_lower to be 13.9042, got {results['median_sigma1_ci_lower']}."
    assert results["median_sigma1_ci_upper"] == 14.1561, f"Expected median_sigma1_ci_upper to be 14.1561, got {results['median_sigma1_ci_upper']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
