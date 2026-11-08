#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

def get_expected_value(fasta_path):
    """
    Computes the expected integration result using the same libraries the user was instructed to install.
    This avoids importing third-party libraries directly into the pytest environment, 
    while still dynamically computing the truth based on the actual FASTA file.
    """
    script = f"""
import numpy as np
from scipy.integrate import solve_ivp, simpson

with open("{fasta_path}", "r") as f:
    lines = f.read().strip().split('\\n')
seq = "".join(lines[1:])
L = len(seq)
G = seq.count('G')
C = seq.count('C')
R = (G + C) / L

def ode(t, y):
    return -R * y + (L / 1000.0) * np.cos(t)

t_eval = np.arange(0, 50.01, 0.01)
sol = solve_ivp(ode, [0, 50], [L], method='RK45', t_eval=t_eval)
area = simpson(sol.y[0], x=t_eval)
print(f"{{area:.3f}}")
"""
    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Failed to compute expected value. Ensure numpy and scipy are installed.\nError: {result.stderr}")
    return result.stdout.strip()

def test_result_file_exists_and_correct():
    result_path = "/home/user/result.txt"
    fasta_path = "/home/user/gene.fasta"

    assert os.path.isfile(fasta_path), f"FASTA file {fasta_path} is missing."
    assert os.path.isfile(result_path), f"Result file {result_path} is missing."

    with open(result_path, "r") as f:
        user_result = f.read().strip()

    expected_result = get_expected_value(fasta_path)

    assert user_result == expected_result, f"Expected result {expected_result}, but got {user_result} in {result_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
