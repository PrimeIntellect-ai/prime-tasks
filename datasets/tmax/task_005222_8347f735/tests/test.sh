#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def compute_expected_k():
    log_path = '/home/user/sim_output.log'
    if not os.path.exists(log_path):
        pytest.fail(f"Required file {log_path} is missing.")

    t_vals = []
    val_vals = []

    with open(log_path, 'r') as f:
        current_t = None
        for line in f:
            line = line.strip()
            if line.startswith('[INFO] t='):
                current_t = float(line.split('=')[1])
            elif line.startswith('[DATA] val='):
                if current_t is not None:
                    val_vals.append(float(line.split('=')[1]))
                    t_vals.append(current_t)
                    current_t = None

    if not t_vals:
        pytest.fail("Could not parse t and val from the log file.")

    # Compute DFT power for w in 1..6
    max_power = -1
    omega_max = 1
    for w in range(1, 7):
        sum_cos = 0.0
        sum_sin = 0.0
        for t, val in zip(t_vals, val_vals):
            sum_cos += val * math.cos(w * t)
            sum_sin += val * math.sin(w * t)
        power = sum_cos**2 + sum_sin**2
        if power > max_power:
            max_power = power
            omega_max = w

    # Newton-Raphson
    k = 1.0
    target = omega_max**2
    for _ in range(5):
        f_k = k + math.exp(-k) - target
        f_prime_k = 1.0 - math.exp(-k)
        k = k - f_k / f_prime_k

    return f"{k:.4f}"

def test_result_file_exists():
    result_path = '/home/user/result.txt'
    assert os.path.exists(result_path), f"Error: The result file {result_path} does not exist."
    assert os.path.isfile(result_path), f"Error: {result_path} is not a file."

def test_result_value():
    result_path = '/home/user/result.txt'
    if not os.path.exists(result_path):
        pytest.fail(f"Result file {result_path} not found.")

    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_val = compute_expected_k()
    assert content == expected_val, f"Error: Expected result to be '{expected_val}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
