#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/pentest_report.json"

def test_report_exists():
    """Verify that the pentest report file exists."""
    assert os.path.isfile(REPORT_PATH), f"The final report file is missing at {REPORT_PATH}."

def test_report_contents():
    """Verify the contents of the pentest report match the expected findings."""
    assert os.path.isfile(REPORT_PATH), f"The final report file is missing at {REPORT_PATH}."

    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {REPORT_PATH} as JSON: {e}")

    # Check port
    assert "open_port" in report_data, "Missing 'open_port' key in the report."
    assert report_data["open_port"] == 10037, f"Incorrect open_port. Expected 10037, got {report_data['open_port']}."

    # Check AES Key
    assert "aes_key" in report_data, "Missing 'aes_key' key in the report."
    assert report_data["aes_key"] == "B4ckD00rK3y_2023", "Incorrect aes_key extracted."

    # Check AES IV
    assert "aes_iv" in report_data, "Missing 'aes_iv' key in the report."
    assert report_data["aes_iv"] == "IV_v3ctor_123456", "Incorrect aes_iv extracted."

    # Check Cracked Passwords
    assert "cracked_passwords" in report_data, "Missing 'cracked_passwords' key in the report."
    passwords = report_data["cracked_passwords"]

    assert isinstance(passwords, dict), "'cracked_passwords' should be a dictionary."

    assert "user1" in passwords, "Missing 'user1' in cracked_passwords."
    assert passwords["user1"] == "4829", f"Incorrect password for user1. Expected '4829', got {passwords['user1']}."

    assert "user2" in passwords, "Missing 'user2' in cracked_passwords."
    assert passwords["user2"] == "1934", f"Incorrect password for user2. Expected '1934', got {passwords['user2']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
