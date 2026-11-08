#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_results_json_exists():
    filepath = '/home/user/results.json'
    assert os.path.isfile(filepath), f"The file {filepath} does not exist. Did you save your results?"

def test_results_json_format_and_values():
    filepath = '/home/user/results.json'
    with open(filepath, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {filepath} is not valid JSON.")

    # Check keys
    expected_keys = {"extracted_real_count", "wasserstein_distance", "kde_prob_mass_40_60"}
    assert set(results.keys()) == expected_keys, f"The JSON keys do not match the expected keys. Found: {list(results.keys())}"

    # Check extracted_real_count
    assert isinstance(results["extracted_real_count"], int), "extracted_real_count must be an integer."
    assert results["extracted_real_count"] == 6, f"Expected extracted_real_count to be 6, got {results['extracted_real_count']}"

    # Check wasserstein_distance
    assert isinstance(results["wasserstein_distance"], (int, float)), "wasserstein_distance must be a float."
    expected_wd = 0.0208333
    assert math.isclose(results["wasserstein_distance"], expected_wd, abs_tol=1e-4), \
        f"Expected wasserstein_distance to be near {expected_wd}, got {results['wasserstein_distance']}"

    # Check kde_prob_mass_40_60
    assert isinstance(results["kde_prob_mass_40_60"], (int, float)), "kde_prob_mass_40_60 must be a float."
    expected_kde = 0.169018
    assert math.isclose(results["kde_prob_mass_40_60"], expected_kde, abs_tol=1e-3), \
        f"Expected kde_prob_mass_40_60 to be near {expected_kde}, got {results['kde_prob_mass_40_60']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
