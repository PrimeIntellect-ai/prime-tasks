#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import pytest

def test_output_files_exist():
    """Verify that the required output files were created."""
    assert os.path.exists("/home/user/output.h5"), "Missing /home/user/output.h5"
    assert os.path.exists("/home/user/norm.log"), "Missing /home/user/norm.log"

def test_ridge_regression_results():
    """Verify the correctness of the Ridge regression estimate and its L2 norm."""

    # We use a subprocess to execute the validation logic since we are restricted to
    # the Python standard library in the test suite itself, but the environment has
    # numpy and h5py installed.
    validation_script = """
import numpy as np
import h5py
import json
import sys

try:
    # Load expected inputs
    with h5py.File('/home/user/input.h5', 'r') as f:
        A = f['A'][:]
        b = f['b'][:]

    # Compute expected Ridge regression result
    lmbda = 1e-4
    I = np.eye(A.shape[1])
    expected_x = np.linalg.inv(A.T @ A + lmbda * I) @ A.T @ b
    expected_norm = np.linalg.norm(expected_x)
    expected_norm_str = f"{expected_norm:.4f}"

    # Read agent's norm.log
    with open('/home/user/norm.log', 'r') as f:
        agent_norm = f.read().strip()

    # Read agent's x_ridge from output.h5
    with h5py.File('/home/user/output.h5', 'r') as f:
        if 'x_ridge' not in f:
            raise KeyError("Dataset 'x_ridge' not found in /home/user/output.h5")
        agent_x = f['x_ridge'][:]

    if agent_x.shape != expected_x.shape:
        raise ValueError(f"Shape mismatch: expected {expected_x.shape}, got {agent_x.shape}")

    max_diff = float(np.max(np.abs(agent_x - expected_x)))

    result = {
        "agent_norm": agent_norm,
        "expected_norm_str": expected_norm_str,
        "max_diff": max_diff
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
"""

    proc = subprocess.run(
        ["python3", "-c", validation_script],
        capture_output=True,
        text=True
    )

    assert proc.returncode == 0, f"Validation script failed to execute. Stderr: {proc.stderr}"

    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse JSON from validation script. Stdout: {proc.stdout}")

    if "error" in result:
        pytest.fail(f"Validation error: {result['error']}")

    # Assert norm string matches exactly
    assert result["agent_norm"] == result["expected_norm_str"], \
        f"Expected norm to be '{result['expected_norm_str']}', but got '{result['agent_norm']}' in /home/user/norm.log"

    # Assert x_ridge is numerically close to expected
    assert result["max_diff"] < 1e-4, \
        f"x_ridge values do not match expected Ridge regression result. Max absolute difference: {result['max_diff']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
