#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

VENV_PYTHON = "/home/user/venv/bin/python"
SIMULATE_SCRIPT = "/home/user/simulate.py"
ESTIMATE_FILE = "/home/user/integral_estimate.txt"
H5_FILE = "/home/user/simulation.h5"

def test_venv_exists():
    """Verify that the virtual environment exists and contains a Python executable."""
    assert os.path.exists(VENV_PYTHON), f"Virtual environment Python executable not found at {VENV_PYTHON}"

def test_simulate_script_exists():
    """Verify that the simulation script was created."""
    assert os.path.exists(SIMULATE_SCRIPT), f"{SIMULATE_SCRIPT} does not exist."
    assert os.path.isfile(SIMULATE_SCRIPT), f"{SIMULATE_SCRIPT} is not a regular file."

def test_run_simulation_script():
    """Run the submitted script from a clean output state."""
    for path in (ESTIMATE_FILE, H5_FILE):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [VENV_PYTHON, SIMULATE_SCRIPT],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The simulation script failed when run with the virtual environment Python.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(ESTIMATE_FILE), f"Running the script did not create {ESTIMATE_FILE}."
    assert os.path.isfile(H5_FILE), f"Running the script did not create {H5_FILE}."

def test_integral_estimate():
    """Verify that the integral estimate text file exists and contains the correct value."""
    estimate_file = ESTIMATE_FILE
    assert os.path.exists(estimate_file), f"{estimate_file} does not exist."

    with open(estimate_file, "r") as f:
        content = f.read().strip()

    # Compute the expected value using the venv's python and numpy
    script = """
import numpy as np
np.random.seed(42)
x = np.random.uniform(0, 2, 1000000)
y = np.random.uniform(0, 1, 1000000)
under = y < np.exp(-x**2)
integral = 2.0 * np.sum(under) / 1000000
print(f"{integral:.5f}")
"""
    result = subprocess.run([VENV_PYTHON, "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run numpy in the virtual environment. Is numpy installed?"

    expected = result.stdout.strip()
    assert content == expected, f"Integral estimate mismatch. Expected '{expected}', got '{content}'."

def test_h5_file():
    """Verify that the HDF5 file contains the exact under-curve observations."""
    h5_file = H5_FILE
    assert os.path.exists(h5_file), f"{h5_file} does not exist."

    # Recompute the required observations and validate the HDF5 contents using
    # the venv's numpy and h5py installations.
    script = """
import sys
try:
    import numpy as np
    import h5py
except ImportError as e:
    print(f"Required package is not installed: {e}")
    sys.exit(1)

np.random.seed(42)
x = np.random.uniform(0, 2, 1000000)
y = np.random.uniform(0, 1, 1000000)
expected = (y < np.exp(-x**2)).reshape(1000, 1000).astype(int)

try:
    with h5py.File('/home/user/simulation.h5', 'r') as f:
        if 'mc_epochs' not in f:
            print("Dataset 'mc_epochs' not found in HDF5 file.")
            sys.exit(1)
        ds = f['mc_epochs']
        if ds.shape != (1000, 1000):
            print(f"Dataset 'mc_epochs' has incorrect shape. Expected (1000, 1000), got {ds.shape}.")
            sys.exit(1)
        if not str(ds.dtype).startswith('int'):
            print(f"Dataset 'mc_epochs' has incorrect dtype. Expected an integer type, got {ds.dtype}.")
            sys.exit(1)
        actual = ds[...]
        if not np.array_equal(actual, expected):
            mismatches = int(np.count_nonzero(actual != expected))
            print(f"Dataset 'mc_epochs' does not contain the required under-curve observations; {mismatches} values differ.")
            sys.exit(1)
except Exception as e:
    print(f"Error reading HDF5 file: {e}")
    sys.exit(1)
"""
    result = subprocess.run([VENV_PYTHON, "-c", script], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"HDF5 validation failed:\n{result.stdout.strip()}\n{result.stderr.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
