#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_optimized_paths_csv_correct():
    file_path = "/home/user/optimized_paths.csv"

    assert os.path.isfile(file_path), f"The expected output file {file_path} does not exist."

    expected_lines = [
        "SYS_04,8",
        "SYS_09,8",
        "SYS_10,9",
        "SYS_07,10",
        "SYS_08,12"
    ]

    with open(file_path, "r") as f:
        # Read lines, strip whitespace, and ignore empty lines
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {file_path} are incorrect. "
        f"Expected: {expected_lines}, but got: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
