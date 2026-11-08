#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def compute_expected_state():
    state = 8472
    for i in range(37):
        if i % 2 == 0:
            state = (state * 3) % 99991
        else:
            state = (state + 17) % 99991
    return state

def test_state_37_file_exists():
    """Test that the output file exists."""
    assert os.path.isfile("/home/user/state_37.txt"), "/home/user/state_37.txt does not exist. You must create it."

def test_state_37_content():
    """Test that the output file contains the correct integer."""
    filepath = "/home/user/state_37.txt"
    assert os.path.isfile(filepath), f"{filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected = str(compute_expected_state())

    assert content == expected, f"The content of {filepath} is incorrect. Expected '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
