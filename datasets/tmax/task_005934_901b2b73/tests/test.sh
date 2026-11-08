#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_compliance_audit_log():
    audit_log_path = "/home/user/compliance_audit.log"

    # Check if the file exists
    assert os.path.isfile(audit_log_path), f"The file {audit_log_path} is missing."

    # Expected content lines
    expected_lines = [
        "RECOVERED_PIN=48291",
        "SSH_VIOLATIONS=3",
        "VIOLATING_KEYS=PasswordAuthentication,PermitRootLogin,X11Forwarding"
    ]

    # Read the actual content
    with open(audit_log_path, "r") as f:
        content = f.read().strip()

    # Process actual lines to ignore trailing whitespaces
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    # Assert exact match
    assert actual_lines == expected_lines, (
        f"The contents of {audit_log_path} do not match the expected final state.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
