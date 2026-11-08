#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_output_file_exists():
    """Test that the output file exists in the correct location."""
    file_path = "/home/user/training_features.tsv"
    assert os.path.exists(file_path), f"The output file {file_path} was not created."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_output_file_content():
    """Test that the output file contains the correct processed data."""
    file_path = "/home/user/training_features.tsv"
    assert os.path.exists(file_path), f"The output file {file_path} does not exist."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "S1\t8.000\t0.000",
        "S5\t7.500\t0.150",
        "S6\t1.500\t0.000",
        "S7\t20.000\t0.000"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
