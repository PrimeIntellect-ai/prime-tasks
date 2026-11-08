#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_audit_report_exists_and_correct():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_password = "audit_trail_123"
    expected_directives = [
        "PasswordAuthentication",
        "PermitRootLogin",
        "X11Forwarding"
    ]

    assert "compromised_password" in report_data, "Missing 'compromised_password' key in audit report."
    assert report_data["compromised_password"] == expected_password, (
        f"Incorrect compromised_password. Expected '{expected_password}', got '{report_data['compromised_password']}'."
    )

    assert "insecure_ssh_directives" in report_data, "Missing 'insecure_ssh_directives' key in audit report."
    actual_directives = report_data["insecure_ssh_directives"]

    assert isinstance(actual_directives, list), "'insecure_ssh_directives' must be a list."
    assert actual_directives == expected_directives, (
        f"Incorrect insecure_ssh_directives. Expected {expected_directives}, got {actual_directives}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
