#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_correlation_result_exists_and_correct():
    result_file = "/home/user/correlation_result.txt"

    # Check if the file exists
    assert os.path.exists(result_file), f"Verification failed: {result_file} not found. Did you save the result?"
    assert os.path.isfile(result_file), f"Verification failed: {result_file} is not a file."

    # Read the file and check its contents
    with open(result_file, "r") as f:
        val = f.read().strip()

    expected_val = "0.999"
    assert val == expected_val, f"Verification failed: expected {expected_val}, got '{val}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
