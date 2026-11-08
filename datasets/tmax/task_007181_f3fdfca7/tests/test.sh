#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_k_estimate_file_exists_and_content():
    file_path = "/home/user/k_estimate.txt"

    # Check if file exists
    assert os.path.isfile(file_path), f"The file {file_path} is missing. Did you save your output?"

    # Read and parse the content
    with open(file_path, "r") as f:
        content = f.read().strip()

    # The expected value based on the least-squares derivation
    # A^T A = 162.2663
    # A^T b = 32.6884
    # k = 32.6884 / 162.2663 = 0.201449...
    # Rounded to 3 decimal places: 0.201
    expected_value = "0.201"

    assert content == expected_value, f"The value in {file_path} is '{content}', expected '{expected_value}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
