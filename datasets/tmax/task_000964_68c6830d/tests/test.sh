#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import pytest

def get_expected_kde():
    """
    Computes the expected KDE output by running a subprocess that uses numpy and h5py.
    This avoids importing third-party libraries directly in the test file, adhering to stdlib-only rules.
    """
    script = """
import numpy as np
import h5py
import json

try:
    with h5py.File('/home/user/mcmc_samples.h5', 'r') as f:
        data = f['trajectories'][:]

    valid_chains = []
    for i in range(data.shape[0]):
        if np.all(np.abs(data[i]) <= 1000.0):
            valid_chains.append(data[i])

    valid_chains = np.array(valid_chains)
    samples = valid_chains[:, :, 0].flatten()

    x_eval = np.linspace(-5.0, 5.0, 100)
    h = 0.5
    N = len(samples)

    expected_kde = []
    for x in x_eval:
        density = (1.0 / (N * h)) * np.sum((1.0 / np.sqrt(2 * np.pi)) * np.exp(-0.5 * ((x - samples) / h)**2))
        expected_kde.append(f"{density:.6f}")

    print(json.dumps(expected_kde))
except Exception as e:
    print(json.dumps({"error": str(e)}))
"""
    result = subprocess.run(['python3', '-c', script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected KDE values. Subprocess error: {result.stderr}")

    output = json.loads(result.stdout)
    if isinstance(output, dict) and "error" in output:
        pytest.fail(f"Error computing expected KDE: {output['error']}")

    return output

def test_output_file_exists():
    """Test that the expected output file has been created."""
    output_file = '/home/user/kde_output.txt'
    assert os.path.exists(output_file), f"The output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"The path {output_file} is not a regular file."

def test_output_file_contents():
    """Test that the output file contains exactly 100 lines with the correct KDE values."""
    output_file = '/home/user/kde_output.txt'

    if not os.path.exists(output_file):
        pytest.fail(f"Output file {output_file} is missing.")

    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 100, f"Expected exactly 100 lines in {output_file}, but found {len(lines)}."

    expected_values = get_expected_kde()

    for i, (actual, expected) in enumerate(zip(lines, expected_values)):
        assert actual == expected, (
            f"Mismatch at line {i + 1}: expected '{expected}', got '{actual}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
