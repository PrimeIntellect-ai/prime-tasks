#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_c_source_file_exists():
    filepath = "/home/user/audit.c"
    assert os.path.isfile(filepath), f"The C source file {filepath} is missing."

def test_executable_exists_and_is_executable():
    filepath = "/home/user/audit"
    assert os.path.isfile(filepath), f"The executable {filepath} is missing."
    assert os.access(filepath, os.X_OK), f"The file {filepath} is not executable."

def test_flagged_paths_csv_exists():
    filepath = "/home/user/flagged_paths.csv"
    assert os.path.isfile(filepath), f"The output file {filepath} is missing."

def test_flagged_paths_csv_content():
    filepath = "/home/user/flagged_paths.csv"
    assert os.path.isfile(filepath), f"The output file {filepath} is missing."

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "A102,A100->A101->A102,11000,1",
        "A102,A100->A104->A102,10000,2",
        "A102,A100->A102,1000,3",
        "A103,A100->A104->A103,11000,1",
        "A105,A100->A101->A105,17000,1",
        "A105,A100->A105,15000,2"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {filepath}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', got: '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
