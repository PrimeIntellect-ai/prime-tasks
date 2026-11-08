#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

EXPECTED_OUTPUT = """3881 algorithm
3805 intelligence
3790 dataset
3779 neural
3759 matrix
3742 tensor
3694 machine
3687 learning
3685 quantum
3678 vector"""

def test_top_tokens_file_exists():
    """Verify that the output file exists."""
    file_path = "/home/user/top_tokens.txt"
    assert os.path.exists(file_path), f"The file {file_path} was not created."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_top_tokens_content():
    """Verify the contents of the top_tokens.txt file."""
    file_path = "/home/user/top_tokens.txt"

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = EXPECTED_OUTPUT.strip().split("\n")
    actual_lines = content.split("\n")

    assert len(actual_lines) == 10, f"Expected exactly 10 lines, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
