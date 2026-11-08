#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_FILE = "/home/user/investigation_result.json"
EXPECTED_MALICIOUS_FILE = "/home/user/webroot/cgi-bin/system_health"
EXPECTED_PERMISSIONS = "4755"
EXPECTED_HIDDEN_KEY = "XyZ89Qlp"

def test_investigation_report_exists():
    """Test that the investigation report JSON file was created."""
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

def test_investigation_report_content():
    """Test that the investigation report contains the correct findings."""
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

    with open(REPORT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")

    assert "malicious_file" in data, "Key 'malicious_file' is missing from the JSON report."
    assert data["malicious_file"] == EXPECTED_MALICIOUS_FILE, \
        f"Expected malicious_file to be '{EXPECTED_MALICIOUS_FILE}', got '{data['malicious_file']}'."

    assert "permissions" in data, "Key 'permissions' is missing from the JSON report."
    assert data["permissions"] == EXPECTED_PERMISSIONS, \
        f"Expected permissions to be '{EXPECTED_PERMISSIONS}', got '{data['permissions']}'."

    assert "hidden_key" in data, "Key 'hidden_key' is missing from the JSON report."
    assert data["hidden_key"] == EXPECTED_HIDDEN_KEY, \
        f"Expected hidden_key to be '{EXPECTED_HIDDEN_KEY}', got '{data['hidden_key']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
