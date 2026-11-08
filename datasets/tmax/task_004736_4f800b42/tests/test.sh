#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pytest

def test_fastcov_library_compiled():
    """Verify that the shared library was compiled successfully."""
    so_path = '/app/fastcov-1.2.0/libfastcov.so'
    assert os.path.isfile(so_path), f"Shared library not found at {so_path}. The fastcov library was not compiled correctly."

def test_dataset_cleaner_c_exists():
    """Verify that the agent wrote the C program."""
    c_path = '/home/user/dataset_cleaner.c'
    assert os.path.isfile(c_path), f"C program not found at {c_path}."

def test_correlations_csv_exists_and_valid():
    """Verify that the output file exists, has the correct shape, and meets the MSE threshold."""
    output_path = '/home/user/correlations.csv'
    dataset_path = '/app/data/sensor_readings.csv'

    assert os.path.isfile(output_path), f"Output file not found at {output_path}."
    assert os.path.isfile(dataset_path), f"Dataset file not found at {dataset_path}."

    try:
        agent_corr = np.loadtxt(output_path, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load {output_path} as a comma-separated CSV of floats: {e}")

    assert agent_corr.shape == (5, 5), f"Expected output matrix shape (5, 5), but got {agent_corr.shape}."

    # Recompute exact correlation matrix from the dataset
    try:
        data = np.loadtxt(dataset_path, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load dataset {dataset_path}: {e}")

    exact_corr = np.corrcoef(data, rowvar=False)

    # Calculate Mean Squared Error
    mse = np.mean((agent_corr - exact_corr)**2)

    threshold = 0.005
    assert mse <= threshold, f"MSE is {mse:.6f}, which is greater than the threshold of {threshold}. The approximation is not accurate enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
