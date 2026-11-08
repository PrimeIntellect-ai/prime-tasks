#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import pytest
import numpy as np
from scipy.optimize import fsolve

def get_expected_results():
    signal_path = '/home/user/signal.npy'
    if not os.path.exists(signal_path):
        pytest.fail(f"Required input file {signal_path} is missing.")

    signals = np.load(signal_path)
    window = np.hanning(1024)
    windowed_signals = signals * window

    fft_res = np.fft.rfft(windowed_signals, axis=1)
    magnitudes = np.abs(fft_res)

    P = np.argmax(magnitudes, axis=1)

    def eq(y, p):
        return y + np.exp(y/100.0) - p

    y_sols = []
    for p in P:
        sol = fsolve(eq, p, args=(p,))[0]
        y_sols.append(sol)

    y_sols = np.array(y_sols)
    y_sols_sorted = np.sort(y_sols)

    mean_val = math.fsum(y_sols_sorted) / 100.0
    expected_text = f"{mean_val:.6f}\n"

    return y_sols_sorted, expected_text.strip()

def test_solutions_npy():
    expected_sols, _ = get_expected_results()

    student_sols_path = '/home/user/solutions.npy'
    assert os.path.exists(student_sols_path), f"File {student_sols_path} does not exist."

    student_sols = np.load(student_sols_path)

    assert student_sols.shape == expected_sols.shape, f"Expected shape {expected_sols.shape}, got {student_sols.shape}"

    # Check if they are sorted
    assert np.all(np.diff(student_sols) >= 0), "The solutions in solutions.npy are not sorted in ascending order."

    # Check values
    np.testing.assert_allclose(
        student_sols, 
        expected_sols, 
        rtol=1e-5, 
        atol=1e-5, 
        err_msg="The values in solutions.npy do not match the expected solutions."
    )

def test_result_txt():
    _, expected_text = get_expected_results()

    result_path = '/home/user/result.txt'
    assert os.path.exists(result_path), f"File {result_path} does not exist."

    with open(result_path, 'r') as f:
        student_text = f.read().strip()

    assert student_text == expected_text, f"Expected result.txt to contain '{expected_text}', but got '{student_text}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
