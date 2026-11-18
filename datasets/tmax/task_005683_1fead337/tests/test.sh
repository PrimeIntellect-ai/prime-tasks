#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_regression_failures_file_exists():
    path = "/home/user/regression_failures.txt"
    assert os.path.isfile(path), f"The expected output file {path} does not exist."

def test_regression_failures_contents():
    path = "/home/user/regression_failures.txt"
    assert os.path.isfile(path), f"The expected output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "data_02.h5",
        "data_03.h5"
    ]

    assert lines == expected_lines, (
        f"Contents of {path} do not match the expected output. "
        f"Expected {expected_lines}, but got {lines}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
