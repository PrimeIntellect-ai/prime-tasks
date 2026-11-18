#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_flagged_rings_csv_exists_and_correct():
    output_path = "/home/user/flagged_rings.csv"
    assert os.path.exists(output_path), f"The output file {output_path} was not created."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Alpha,Beta,Gamma",
        "Epsilon,Eta,Theta,Zeta"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the CSV, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
