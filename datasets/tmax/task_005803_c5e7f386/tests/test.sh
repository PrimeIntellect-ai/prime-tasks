#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import json
import subprocess
import pytest

def get_expected_results():
    script = """
import numpy as np
import scipy.integrate as integrate
from scipy.optimize import curve_fit
import json

samples = np.loadtxt('/home/user/samples.csv')
hist, bin_edges = np.histogram(samples, bins=50, range=(-5, 5), density=True)
bin_centers = (bin_edges[:-1] + bin_edges[1:]) / 2

def Z(a, b):
    res, _ = integrate.quad(lambda t: np.exp(-a*t**2 - b*t**4), -5, 5)
    return res

def f_fit(x_data, a, b):
    z = Z(a, b)
    return np.exp(-a*x_data**2 - b*x_data**4) / z

popt, pcov = curve_fit(f_fit, bin_centers, hist, p0=[1.0, 0.1])
a_opt, b_opt = popt

def L2_integrand(x):
    z = Z(a_opt, b_opt)
    fx = np.exp(-a_opt*x**2 - b_opt*x**4) / z
    nx = np.exp(-x**2/2) / np.sqrt(2*np.pi)
    return (fx - nx)**2

L2_sq, _ = integrate.quad(L2_integrand, -5, 5)
L2_dist = np.sqrt(L2_sq)

expected_results = {
    "a": round(a_opt, 4),
    "b": round(b_opt, 4),
    "L2_distance": round(L2_dist, 4)
}

print(json.dumps(expected_results))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected results: {result.stderr}")
    return json.loads(result.stdout)

def test_results_json_exists_and_correct():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"The file {results_path} is missing."
    assert os.path.isfile(results_path), f"The path {results_path} is not a file."

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_path} is not valid JSON.")

    expected = get_expected_results()

    for key in ["a", "b", "L2_distance"]:
        assert key in results, f"Key '{key}' is missing from {results_path}."

        user_val = results[key]
        expected_val = expected[key]

        assert isinstance(user_val, (int, float)), f"Value for '{key}' must be a number."

        # Allow a tolerance of 1e-4
        assert abs(user_val - expected_val) <= 1.0001e-4, \
            f"Value for '{key}' is {user_val}, expected approximately {expected_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
