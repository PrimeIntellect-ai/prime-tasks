#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def test_report_json_exists_and_valid():
    """Check if report.json exists and contains valid JSON."""
    file_path = "/home/user/report.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Ensure you saved the report."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert isinstance(data, dict), f"JSON in {file_path} must be an object/dictionary."

def test_report_json_content():
    """Check if report.json contains the correct findings."""
    file_path = "/home/user/report.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        data = json.load(f)

    assert "attacker_ip" in data, "Key 'attacker_ip' is missing from report.json."
    assert "c2_ip" in data, "Key 'c2_ip' is missing from report.json."

    # The attacker IP is derived from the Shellshock payload in the access.log
    assert data["attacker_ip"] == "10.0.5.55", "The 'attacker_ip' in report.json is incorrect."

    # The C2 IP is derived from the dropped_malware.elf binary
    assert data["c2_ip"] == "203.0.113.85", "The 'c2_ip' in report.json is incorrect."

def test_redacted_access_log_exists():
    """Check if redacted_access.log exists."""
    file_path = "/home/user/redacted_access.log"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Ensure you created the redacted log."

def test_redacted_access_log_content():
    """Check if redacted_access.log has been properly sanitized."""
    original_path = "/home/user/incident_data/access.log"
    redacted_path = "/home/user/redacted_access.log"

    assert os.path.isfile(original_path), f"Original log {original_path} is missing."
    assert os.path.isfile(redacted_path), f"Redacted log {redacted_path} is missing."

    with open(original_path, "r") as f:
        original_lines = f.readlines()

    with open(redacted_path, "r") as f:
        redacted_lines = f.readlines()

    assert len(original_lines) == len(redacted_lines), "Redacted log does not have the same number of lines as the original log."

    for i, (orig, redacted) in enumerate(zip(original_lines, redacted_lines)):
        # Compute the expected redacted line
        expected = re.sub(r'session_token=[a-zA-Z0-9]+', 'session_token=REDACTED', orig)
        expected = re.sub(r'password=[a-zA-Z0-9]+', 'password=REDACTED', expected)

        assert redacted == expected, f"Line {i+1} in redacted_access.log is not correctly redacted.\nExpected: {expected}\nGot: {redacted}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
