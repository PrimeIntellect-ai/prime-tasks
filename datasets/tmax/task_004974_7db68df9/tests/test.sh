#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest
import math

def test_ols_coeffs_output():
    """Test that the OLS coefficients are correctly calculated and formatted."""
    file_path = '/home/user/ols_coeffs.txt'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    # Remove all whitespace to handle optional spaces after commas
    content_no_spaces = content.replace(" ", "")

    expected_coeffs = "3.00,2.00,-1.50"
    assert content_no_spaces == expected_coeffs, f"Expected OLS coefficients '{expected_coeffs}', but got '{content}'."

def test_entropy_output():
    """Test that the Shannon entropy is correctly calculated and formatted."""
    file_path = '/home/user/entropy.txt'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_entropy = "0.9710"
    assert content == expected_entropy, f"Expected entropy '{expected_entropy}', but got '{content}'."

def test_rmse_output():
    """Test that the RMSE is correctly calculated and formatted."""
    file_path = '/home/user/rmse.txt'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_rmse = "0.6455"
    assert content == expected_rmse, f"Expected RMSE '{expected_rmse}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
