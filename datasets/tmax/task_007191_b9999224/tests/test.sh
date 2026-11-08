#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_model_mse_file():
    filepath = "/home/user/model_mse.tsv"

    # Check if the output file was created
    assert os.path.exists(filepath), f"Expected output file {filepath} was not found."
    assert os.path.isfile(filepath), f"{filepath} is a directory, expected a file."

    # Read the contents of the file
    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Expected output
    expected_lines = [
        "S1\t0.007",
        "S2\t0.005",
        "S3\t0.025"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {filepath}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
