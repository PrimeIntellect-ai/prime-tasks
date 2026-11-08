#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_leak_report_exists():
    """Check if the leak_report.txt file exists."""
    file_path = "/home/user/leak_report.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist. The task is incomplete."

def test_leak_report_content():
    """Check if the leak_report.txt contains the correct leaked dataset filename."""
    file_path = "/home/user/leak_report.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_filename = "test_split_beta.csv"
    assert content == expected_filename, f"Expected '{expected_filename}', but got '{content}' in {file_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
