#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_answer_file_exists():
    """Test that the answer.txt file exists."""
    answer_path = "/home/user/answer.txt"
    assert os.path.isfile(answer_path), f"File {answer_path} is missing."

def test_answer_file_content():
    """Test that the answer.txt file contains the correct extracted x and computed result."""
    answer_path = "/home/user/answer.txt"
    with open(answer_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {answer_path}, found {len(lines)}."

    # Parse x
    x_match = re.match(r"^x:\s*([0-9\.eE+-]+)$", lines[0])
    assert x_match, f"First line '{lines[0]}' does not match expected format 'x: [value]'."
    x_value = float(x_match.group(1))

    # Parse result
    result_match = re.match(r"^result:\s*([0-9\.eE+-]+)$", lines[1])
    assert result_match, f"Second line '{lines[1]}' does not match expected format 'result: [value]'."
    result_value = float(result_match.group(1))

    # Check x value
    expected_x = 1e-8
    assert abs(x_value - expected_x) < 1e-10, f"Extracted x value is {x_value}, expected {expected_x}."

    # Check result value
    expected_result = 0.5
    assert abs(result_value - expected_result) < 1e-6, f"Computed result is {result_value}, expected {expected_result}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
