#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_environment_diffs_exists():
    path = "/home/user/environment_diffs.csv"
    assert os.path.isfile(path), f"Output file missing: {path}"

def test_environment_diffs_content():
    path = "/home/user/environment_diffs.csv"
    assert os.path.isfile(path), f"Output file missing: {path}"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"File {path} is empty."

    header = lines[0]
    expected_header = "Environment,Server1,Server2,IsExactMatch,JaccardScore"
    assert header == expected_header, f"Header mismatch. Expected '{expected_header}', got '{header}'"

    expected_rows = [
        "dev,delta,epsilon,0,0.40",
        "dev,delta,zeta,0,0.40",
        "dev,epsilon,zeta,1,1.00",
        "prod,alpha,beta,1,1.00",
        "prod,alpha,gamma,0,0.67",
        "prod,beta,gamma,0,0.67"
    ]

    actual_rows = lines[1:]

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected '{expected}', got '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
