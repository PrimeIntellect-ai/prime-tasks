#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

OUTPUT_FILE = "/home/user/omega_imputed.csv"

EXPECTED_CONTENT = """timestamp,temperature,load
2023-10-01 10:00:00,44.00,1.2
2023-10-01 10:01:00,46.00,1.3
2023-10-01 10:02:00,48.00,1.4
2023-10-01 10:03:00,50.00,1.5
2023-10-01 10:04:00,51.50,1.45
2023-10-01 10:05:00,53.00,1.5
2023-10-01 10:06:00,54.50,1.6
2023-10-01 10:07:00,56.00,1.7"""

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."

def test_output_file_contents():
    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()

    expected_lines = EXPECTED_CONTENT.strip().split("\n")
    actual_lines = content.split("\n")

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows (including header), but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual.strip() == expected.strip(), f"Row {i+1} mismatch. Expected: '{expected.strip()}', but got: '{actual.strip()}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
