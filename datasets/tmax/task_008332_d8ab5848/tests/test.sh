#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/audit_report.json"

def test_audit_report_exists():
    """Verify that the audit report JSON file exists."""
    assert os.path.exists(REPORT_PATH), f"Verification failed: {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"Verification failed: {REPORT_PATH} is not a file."

def test_audit_report_valid_json():
    """Verify that the audit report is valid JSON."""
    assert os.path.exists(REPORT_PATH), f"Verification failed: {REPORT_PATH} does not exist."
    with open(REPORT_PATH, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Verification failed: {REPORT_PATH} is not valid JSON.")

def test_audit_report_contents():
    """Verify that the audit report contains the correct cracked passphrase and extracted cookie."""
    assert os.path.exists(REPORT_PATH), f"Verification failed: {REPORT_PATH} does not exist."

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Verification failed: {REPORT_PATH} is not valid JSON.")

    assert "cracked_passphrase" in data, "Verification failed: 'cracked_passphrase' key missing in JSON."
    assert data["cracked_passphrase"] == "6194", f"Verification failed: Incorrect passphrase. Expected '6194', got '{data['cracked_passphrase']}'."

    assert "audit_session_cookie" in data, "Verification failed: 'audit_session_cookie' key missing in JSON."
    assert data["audit_session_cookie"] == "sec_token_88ab49f2b3", f"Verification failed: Incorrect audit_session_cookie. Expected 'sec_token_88ab49f2b3', got '{data['audit_session_cookie']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
