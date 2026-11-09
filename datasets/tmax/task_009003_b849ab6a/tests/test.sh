#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np


def test_result_file_exists():
    """Test that the result.txt file was created."""
    file_path = "/home/user/result.txt"
    assert os.path.isfile(file_path), f"Missing file: {file_path}. The C program must create this file."


def test_result_content_matches_expected():
    """Test that result.txt exactly matches the result derived from the input data."""
    result_path = "/home/user/result.txt"
    spectra_path = "/home/user/spectra.csv"

    assert os.path.isfile(result_path), f"Missing file: {result_path}"
    assert os.path.isfile(spectra_path), f"Missing file: {spectra_path}"

    data = np.loadtxt(spectra_path, delimiter=",")
    assert data.shape == (50, 10), f"Unexpected spectroscopy data shape: {data.shape}"

    covariance = np.cov(data, rowvar=False)
    singular_values = np.linalg.svd(
        covariance + 0.01 * np.eye(10), compute_uv=False
    )
    condition_number = singular_values.max() / singular_values.min()
    selected_lambda = 0.5 if condition_number > 500 else 0.01
    lower = np.linalg.cholesky(
        covariance + selected_lambda * np.eye(10)
    )
    expected_content = (
        f"Lambda: {selected_lambda:.4f}, Trace: {np.trace(lower):.4f}"
    )

    with open(result_path, "r") as f:
        result_content = f.read().strip()

    assert result_content == expected_content, (
        f"Content mismatch in {result_path}.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{result_content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
