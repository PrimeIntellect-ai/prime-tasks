#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_csv_file_exists():
    csv_path = "/home/user/top_502_ips.csv"
    assert os.path.isfile(csv_path), f"The output file {csv_path} does not exist."

def test_csv_file_content():
    csv_path = "/home/user/top_502_ips.csv"
    assert os.path.isfile(csv_path), f"The output file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Rank,IP,Count",
        "1,192.168.1.50,8",
        "2,10.0.0.99,5",
        "3,172.16.5.18,3"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', but got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
