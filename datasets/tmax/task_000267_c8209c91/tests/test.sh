#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import pytest

def get_expected_value():
    """
    Computes the expected Wasserstein distance using numpy in a subprocess.
    This avoids importing third-party libraries directly in the pytest file
    while still dynamically deriving the expected truth value.
    """
    code = """
import numpy as np
import math

def get_data(x):
    base_signal = math.exp(-200 * (x - 0.55)**2)
    freqs = [1, 2, 3, 4, 5]
    return [base_signal * math.cos(f * x) + 0.1 * math.sin(f * 10 * x) for f in freqs]

x_init = np.linspace(0, 1.0, 11)
M = np.array([get_data(x) for x in x_init])
U, S, Vt = np.linalg.svd(M, full_matrices=False)
S_truncated = np.zeros_like(S)
S_truncated[:2] = S[:2]
M_denoised_init = U @ np.diag(S_truncated) @ Vt

def project(v):
    v_proj = np.zeros_like(v)
    for i in range(2):
         v_proj += np.dot(v, Vt[i]) * Vt[i]
    return v_proj

def calc_S(v):
    return np.sum(v**2)

points = list(x_init)
S_vals = [calc_S(M_denoised_init[i]) for i in range(len(x_init))]

while True:
    refined = False
    new_points = []
    new_S_vals = []
    for i in range(len(points) - 1):
        new_points.append(points[i])
        new_S_vals.append(S_vals[i])

        if abs(S_vals[i] - S_vals[i+1]) > 0.5:
            x_mid = (points[i] + points[i+1]) / 2.0
            v_raw = np.array(get_data(x_mid))
            v_proj = project(v_raw)
            s_mid = calc_S(v_proj)
            new_points.append(x_mid)
            new_S_vals.append(s_mid)
            refined = True

    new_points.append(points[-1])
    new_S_vals.append(S_vals[-1])

    points = new_points
    S_vals = new_S_vals

    if not refined:
        break

points = np.array(points)
S_vals = np.array(S_vals)

A = np.trapz(S_vals, points)
P = S_vals / A

C = np.zeros_like(P)
for i in range(1, len(points)):
    C[i] = C[i-1] + 0.5 * (points[i] - points[i-1]) * (P[i] + P[i-1])

W = 0.0
for i in range(len(points) - 1):
    w_i = 0.5 * (points[i+1] - points[i]) * (abs(C[i] - points[i]) + abs(C[i+1] - points[i+1]))
    W += w_i

print(round(W, 6))
"""
    result = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected value: {result.stderr}")
    try:
        return float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Could not parse expected value from output: {result.stdout}")

def test_result_file_exists():
    path = '/home/user/result.txt'
    assert os.path.exists(path), f"File {path} is missing. The analysis script must create this file."
    assert os.path.isfile(path), f"Path {path} exists but is not a regular file."

def test_result_value_correct():
    path = '/home/user/result.txt'
    if not os.path.exists(path):
        pytest.fail(f"Cannot check value because {path} does not exist.")

    with open(path, 'r') as f:
        content = f.read().strip()

    try:
        actual_value = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} is not a valid float: '{content}'")

    expected_value = get_expected_value()

    # Allow a small tolerance for floating point rounding differences
    assert abs(actual_value - expected_value) <= 1e-5, \
        f"The calculated Wasserstein distance is incorrect. Expected ~{expected_value}, got {actual_value}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
