#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def test_slope_file_exists_and_correct():
    slope_file = "/home/user/slope.txt"
    assert os.path.exists(slope_file), f"File {slope_file} is missing."
    assert os.path.isfile(slope_file), f"Path {slope_file} is not a file."

    with open(slope_file, "r") as f:
        content = f.read().strip()

    assert content, f"File {slope_file} is empty."

    try:
        slope_val = float(content)
    except ValueError:
        pytest.fail(f"Content of {slope_file} is not a valid float: '{content}'")

    # Time2 = 400, Time1 = 150
    # Cond2 = 5e11, Cond1 = 2e10
    expected_slope = (400 - 150) / (5e11 - 2e10)

    # Check if it's close enough (relative tolerance of 1e-4 should be safe for awk output)
    assert math.isclose(slope_val, expected_slope, rel_tol=1e-4), \
        f"Slope value {slope_val} in {slope_file} is not close to expected {expected_slope}."

def test_unstable_matrices_file_exists_and_correct():
    unstable_file = "/home/user/unstable_matrices.txt"
    assert os.path.exists(unstable_file), f"File {unstable_file} is missing."
    assert os.path.isfile(unstable_file), f"Path {unstable_file} is not a file."

    with open(unstable_file, "r") as f:
        content = f.read().strip()

    expected_ids = ["5", "6", "7"]
    actual_ids = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_ids == expected_ids, \
        f"Content of {unstable_file} does not match expected IDs. Expected {expected_ids}, got {actual_ids}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
