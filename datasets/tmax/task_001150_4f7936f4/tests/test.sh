#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import sys
import subprocess
import pytest

def get_expected_results():
    """
    Computes the expected results dynamically using the environment's libraries,
    since the test itself must only import standard libraries.
    """
    script = """
import numpy as np
import pandas as pd
import json
from scipy.stats import gaussian_kde

try:
    df = pd.read_csv('/home/user/samples.csv')
    theta = df['theta'].values

    mean_val = np.mean(theta)

    np.random.seed(42)
    bootstrap_means = [np.mean(np.random.choice(theta, size=len(theta), replace=True)) for _ in range(1000)]
    ci_lower = np.percentile(bootstrap_means, 2.5)
    ci_upper = np.percentile(bootstrap_means, 97.5)

    kde = gaussian_kde(theta)
    log_pdf = float(kde.logpdf(mean_val)[0])

    print(json.dumps({
        "mean": float(mean_val),
        "ci_lower": float(ci_lower),
        "ci_upper": float(ci_upper),
        "log_pdf_at_mean": log_pdf
    }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected results: {result.stderr}")

    data = json.loads(result.stdout)
    if "error" in data:
        pytest.fail(f"Error computing expected results: {data['error']}")
    return data

def test_analyze_script_exists():
    """Test that the analyze.py script was created."""
    assert os.path.isfile("/home/user/analyze.py"), "The script /home/user/analyze.py does not exist."

def test_results_json_exists():
    """Test that the results.json file was generated."""
    assert os.path.isfile("/home/user/results.json"), "The results file /home/user/results.json was not generated."

def test_results_json_content():
    """Test that results.json contains the correct keys and values."""
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), "Missing /home/user/results.json"

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected = get_expected_results()

    expected_keys = {"mean", "ci_lower", "ci_upper", "log_pdf_at_mean"}
    actual_keys = set(results.keys())

    missing_keys = expected_keys - actual_keys
    extra_keys = actual_keys - expected_keys

    assert not missing_keys, f"results.json is missing keys: {missing_keys}"
    assert not extra_keys, f"results.json has unexpected extra keys: {extra_keys}"

    # Check values with a small tolerance
    tolerance = 1e-5
    for key in expected_keys:
        expected_val = expected[key]
        actual_val = results[key]
        assert isinstance(actual_val, (int, float)), f"Value for {key} must be a number."
        assert math.isclose(actual_val, expected_val, rel_tol=tolerance, abs_tol=tolerance), \
            f"Value for {key} is incorrect. Expected {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
