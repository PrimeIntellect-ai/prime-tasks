#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_analysis_report_exists_and_content():
    report_path = "/home/user/analysis_report.txt"

    # Check if the report file exists
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    # Read the contents of the report file
    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "Max_Derivative: 3.00\n"
        "Divergence_Pos: 16\n"
        "Initial_Slope: 1.99"
    )

    # Compare line by line to give better error messages
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = expected_content.splitlines()

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {report_path}, but found {len(actual_lines)}."
    )

    for actual, expected in zip(actual_lines, expected_lines):
        assert actual == expected, f"Line mismatch in {report_path}: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
