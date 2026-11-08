#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_result_csv_exists_and_correct():
    fasta_path = "/home/user/data.fasta"
    result_path = "/home/user/result.csv"
    script_path = "/home/user/fit_model.py"

    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."

    assert os.path.exists(result_path), f"The file {result_path} does not exist. Did you run the script and save the output?"
    assert os.path.isfile(result_path), f"The path {result_path} is not a file."

    # Compute the expected result dynamically
    with open(fasta_path, "r") as f:
        seq = "".join(line.strip() for line in f if not line.startswith(">"))

    # Extract windows of length 10
    windows = [seq[i:i+10] for i in range(0, len(seq), 10)]
    windows = [w for w in windows if len(w) == 10]

    # Calculate GC fractions
    gc_fractions = [sum(1 for c in w if c in "GC") / 10.0 for w in windows]

    y_prev = gc_fractions[:-1]
    y_curr = gc_fractions[1:]

    alpha = 0.5
    beta = 0.5
    lr = 0.1
    iterations = 0

    def calc_mse(a, b):
        return sum((y_curr[i] - (a * y_prev[i] + b))**2 for i in range(len(y_curr))) / len(y_curr)

    prev_mse = calc_mse(alpha, beta)

    for i in range(10000):
        iterations += 1
        grad_alpha = 0.0
        grad_beta = 0.0
        for j in range(len(y_curr)):
            pred = alpha * y_prev[j] + beta
            error = pred - y_curr[j]
            grad_alpha += 2 * error * y_prev[j]
            grad_beta += 2 * error

        grad_alpha /= len(y_curr)
        grad_beta /= len(y_curr)

        # Clip gradients
        grad_alpha = max(-1.0, min(1.0, grad_alpha))
        grad_beta = max(-1.0, min(1.0, grad_beta))

        alpha -= lr * grad_alpha
        beta -= lr * grad_beta

        curr_mse = calc_mse(alpha, beta)
        if abs(prev_mse - curr_mse) < 1e-5:
            break
        prev_mse = curr_mse

    expected_csv = f"{alpha:.4f},{beta:.4f},{iterations}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == expected_csv, f"The content of {result_path} does not match the expected output. Expected: '{expected_csv}', but got: '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
