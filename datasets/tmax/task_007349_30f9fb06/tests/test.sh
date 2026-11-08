#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_correlation_result_file():
    result_file = "/home/user/correlation_result.txt"
    truth_file = "/tests/.expected_truth"

    assert os.path.isfile(result_file), f"The file {result_file} does not exist."
    assert os.path.isfile(truth_file), f"The truth file {truth_file} does not exist."

    with open(truth_file, 'r') as f:
        try:
            expected_val = float(f.read().strip())
        except ValueError:
            pytest.fail("Could not parse the expected truth value as a float.")

    with open(result_file, 'r') as f:
        try:
            actual_val = float(f.read().strip())
        except ValueError:
            pytest.fail(f"Could not parse the contents of {result_file} as a float.")

    diff = abs(expected_val - actual_val)
    assert diff < 0.001, f"Calculated correlation {actual_val} differs from expected {expected_val} by {diff}, which is >= 0.001"

def test_calc_corr_script_fixed():
    script_path = "/home/user/calc_corr.sh"
    dataset_path = "/home/user/dataset.csv"
    truth_file = "/tests/.expected_truth"

    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    try:
        output = subprocess.check_output([script_path, dataset_path], text=True).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running {script_path} failed with error: {e}")

    try:
        actual_val = float(output)
    except ValueError:
        pytest.fail(f"Output of {script_path} is not a valid float: '{output}'")

    with open(truth_file, 'r') as f:
        expected_val = float(f.read().strip())

    diff = abs(expected_val - actual_val)
    assert diff < 0.001, f"Script output {actual_val} differs from expected {expected_val} by {diff}, which is >= 0.001"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
