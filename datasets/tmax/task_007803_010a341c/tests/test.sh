#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def compute_expected():
    data_path = '/home/user/data.txt'
    ref_path = '/home/user/reference.txt'

    if not os.path.exists(data_path) or not os.path.exists(ref_path):
        return None, None, None

    with open(data_path, 'r') as f:
        data = [float(line.strip()) for line in f if line.strip()]

    with open(ref_path, 'r') as f:
        ref = [float(line.strip()) for line in f if line.strip()]

    x0 = 0.0
    gamma = 1.0
    alpha = 0.5
    iterations = 500
    N = len(data)

    for _ in range(iterations):
        grad_x0 = 0.0
        grad_gamma = 0.0
        for val in data:
            diff = val - x0
            denom = 1.0 + (diff / gamma)**2
            grad_x0 += (-2.0 * diff / (gamma * gamma)) / denom
            grad_gamma += (-2.0 * diff * diff / (gamma * gamma * gamma)) / denom

        grad_x0 /= N
        grad_gamma = (1.0 / gamma) + (grad_gamma / N)

        x0 -= alpha * grad_x0
        gamma -= alpha * grad_gamma

    mnll_ref = 0.0
    for val in ref:
        diff_ref = val - x0
        denom_ref = 1.0 + (diff_ref / gamma)**2
        mnll_ref += math.log(denom_ref)

    mnll_ref = math.log(math.pi) + math.log(gamma) + (mnll_ref / len(ref))

    return x0, gamma, mnll_ref

def test_params_output():
    """Verify that params.txt contains the correct fitted parameters."""
    params_path = '/home/user/params.txt'
    assert os.path.exists(params_path), f"Expected output file {params_path} does not exist."

    x0, gamma, _ = compute_expected()
    assert x0 is not None, "Could not compute expected values due to missing data files."

    expected_content = f"x0={x0:.4f}, gamma={gamma:.4f}"

    with open(params_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {params_path} is incorrect. Expected '{expected_content}', got '{content}'."

def test_eval_output():
    """Verify that eval.txt contains the correct evaluation metric."""
    eval_path = '/home/user/eval.txt'
    assert os.path.exists(eval_path), f"Expected output file {eval_path} does not exist."

    _, _, mnll_ref = compute_expected()
    assert mnll_ref is not None, "Could not compute expected values due to missing data files."

    expected_content = f"MNLL={mnll_ref:.4f}"

    with open(eval_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {eval_path} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
