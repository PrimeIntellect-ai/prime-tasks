#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_correlation_file_exists():
    """Check if the correlation.txt file was created."""
    path = "/home/user/correlation.txt"
    assert os.path.isfile(path), f"Error: {path} does not exist."

def test_correlation_value():
    """Check if correlation.txt contains the correct rounded Pearson correlation coefficient."""
    path = "/home/user/correlation.txt"
    assert os.path.isfile(path), f"Error: {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "0.9831"
    assert content == expected, f"Error: Expected correlation to be '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
