#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_convergence_rate_file_exists():
    """Test that the output file exists."""
    file_path = "/home/user/convergence_rate.txt"
    assert os.path.isfile(file_path), f"The output file does not exist: {file_path}"

def test_convergence_rate_content():
    """Test that the output file contains the correct convergence rate."""
    file_path = "/home/user/convergence_rate.txt"
    assert os.path.isfile(file_path), f"The output file does not exist: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_value = "-0.6481"
    assert content == expected_value, f"Expected convergence rate to be '{expected_value}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
