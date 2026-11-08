#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_risk_output_exists():
    """Check if the final output file exists."""
    output_path = "/home/user/risk_output.csv"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a regular file."

def test_risk_output_contents():
    """Check if the final output file has the correct contents."""
    output_path = "/home/user/risk_output.csv"

    expected_lines = [
        "ID,Risk",
        "1,0",
        "3,1",
        "4,0",
        "5,1",
        "8,1",
        "9,0"
    ]

    with open(output_path, "r") as f:
        # Read lines, stripping trailing whitespace like newlines or carriage returns
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {output_path} are incorrect.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
