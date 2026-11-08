#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_audit_report_exists_and_correct():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Password: secret2023",
        "ChainValid: True",
        "PermissionFlag: PermCheck-Fail-RootAccess"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == 3, f"Expected exactly 3 lines in the report, found {len(actual_lines)}."

    assert actual_lines[0] == expected_lines[0], f"Expected first line to be '{expected_lines[0]}', got '{actual_lines[0]}'."
    assert actual_lines[1] == expected_lines[1], f"Expected second line to be '{expected_lines[1]}', got '{actual_lines[1]}'."
    assert actual_lines[2] == expected_lines[2], f"Expected third line to be '{expected_lines[2]}', got '{actual_lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
