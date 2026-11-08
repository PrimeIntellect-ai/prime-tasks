#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import pytest

def test_script_exists():
    """Verify that the user script was created."""
    assert os.path.exists('/home/user/fit_distribution.py'), "/home/user/fit_distribution.py is missing."

def test_result_format():
    """Verify that result.txt exists and is correctly formatted."""
    result_path = '/home/user/result.txt'
    assert os.path.exists(result_path), f"{result_path} is missing."

    with open(result_path, 'r') as f:
        text = f.read().strip()

    parts = text.split(',')
    assert len(parts) == 2, f"Expected 2 comma-separated values in result.txt, got {len(parts)}."

    try:
        a = float(parts[0])
        b = float(parts[1])
    except ValueError:
        pytest.fail(f"Values in result.txt could not be parsed as floats: {text}")

def test_optimality():
    """Verify that the generated parameters yield a valid solution and low Wasserstein distance."""
    # We use a subprocess to run the scipy/numpy verification since third-party imports 
    # are restricted in the pytest file itself.
    checker_script = """
import numpy as np
from scipy.optimize import root, minimize
from scipy.stats import wasserstein_distance
from scipy.special import softmax
import sys

target = np.array([0.1, 0.2, 0.3, 0.2, 0.2])
states = np.arange(5)

def solve_y(a, b):
    def equations(y):
        eqs = np.zeros(5)
        for i in range(5):
            eqs[i] = y[i] - a * np.sin(y[(i+1)%5]) - b * np.cos(y[(i-1)%5]) - i/10.0
        return eqs
    sol = root(equations, np.zeros(5), method='lm')
    return sol.x

def objective(a, b):
    y = solve_y(a, b)
    p = softmax(y)
    return wasserstein_distance(states, states, p, target)

def obj_wrap(params):
    return objective(params[0], params[1])

res = minimize(obj_wrap, [0.0, 0.0], bounds=[(-2, 2), (-2, 2)])
expected_min = res.fun

with open('/home/user/result.txt', 'r') as f:
    a_str, b_str = f.read().strip().split(',')
    a_val, b_val = float(a_str), float(b_str)

dist = objective(a_val, b_val)
if dist <= expected_min + 0.05:
    sys.exit(0)
else:
    print(f"Distance {dist:.4f} is too far from optimal {expected_min:.4f}")
    sys.exit(1)
"""
    result = subprocess.run(
        [sys.executable, "-c", checker_script],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Optimality check failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
