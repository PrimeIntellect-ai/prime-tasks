#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_result_csv_exists_and_correct():
    result_path = "/home/user/result.csv"
    assert os.path.isfile(result_path), f"Expected output file {result_path} does not exist. The script did not create the required output."

    with open(result_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "U5,3",
        "U2,2"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {result_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i + 1} in {result_path}: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
