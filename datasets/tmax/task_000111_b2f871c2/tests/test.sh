#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_investigation_report_exists_and_correct():
    report_path = "/home/user/investigation_report.txt"
    assert os.path.isfile(report_path), f"The investigation report was not found at {report_path}."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Password: s0perS3cret2023!",
        "Attacker IP: 10.0.0.99",
        "Session ID: 7x9Y2aBcD4eF6gH8"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    for expected in expected_lines:
        assert expected in actual_lines, f"Expected line '{expected}' not found in the investigation report."

    # Optional: check exact match
    assert len(actual_lines) == 3, f"The investigation report should contain exactly 3 lines, but found {len(actual_lines)}."
    assert actual_lines[0] == expected_lines[0], f"First line should be '{expected_lines[0]}', but got '{actual_lines[0]}'."
    assert actual_lines[1] == expected_lines[1], f"Second line should be '{expected_lines[1]}', but got '{actual_lines[1]}'."
    assert actual_lines[2] == expected_lines[2], f"Third line should be '{expected_lines[2]}', but got '{actual_lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
