#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import pytest

def test_output_file_exists():
    output_file = '/home/user/output.h5'
    assert os.path.exists(output_file), f"The required output file {output_file} is missing."
    assert os.path.isfile(output_file), f"The path {output_file} exists but is not a file."

def test_output_correctness():
    # We use a subprocess to run the validation script because the test environment
    # must only use standard libraries, but the container has numpy and h5py installed.
    validation_script = """
import numpy as np
import h5py
import sys

try:
    with h5py.File('/home/user/input.h5', 'r') as f:
        A = f['A'][:]
        s = f['s'][:]
except Exception as e:
    print(f"Failed to read input.h5: {e}")
    sys.exit(1)

# Compute true Laplacian
D = np.diag(np.sum(A, axis=1))
L = D - A

# SVD and low-rank approximation
U, S, Vt = np.linalg.svd(L)
S_k = S[:5]
U_k = U[:, :5]
Vt_k = Vt[:5, :]
L_approx = U_k @ np.diag(S_k) @ Vt_k

# Simulate diffusion
x = s.copy()
dt = 0.1
for _ in range(10):
    x = x - dt * (L_approx @ x)

try:
    with h5py.File('/home/user/output.h5', 'r') as f:
        if 'x_final' not in f:
            print("Dataset 'x_final' not found in output.h5")
            sys.exit(1)
        x_final_agent = f['x_final'][:]
except Exception as e:
    print(f"Failed to read output.h5: {e}")
    sys.exit(1)

if not np.allclose(x, x_final_agent, atol=1e-5):
    print("Agent's x_final does not match the expected values.")
    sys.exit(1)

print("SUCCESS")
"""
    result = subprocess.run([sys.executable, "-c", validation_script], capture_output=True, text=True)

    assert result.returncode == 0, f"Correctness validation failed:\n{result.stdout}\n{result.stderr}"
    assert "SUCCESS" in result.stdout, "Validation did not complete successfully."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
