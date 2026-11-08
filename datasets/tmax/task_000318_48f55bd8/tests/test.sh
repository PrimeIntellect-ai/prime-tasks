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
    assert os.path.isfile(REPORT_PATH), f"Audit report not found at {REPORT_PATH}."

def test_audit_report_is_valid_json():
    assert os.path.isfile(REPORT_PATH), f"Audit report not found at {REPORT_PATH}."
    try:
        with open(REPORT_PATH, 'r') as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

def test_audit_report_contents():
    assert os.path.isfile(REPORT_PATH), f"Audit report not found at {REPORT_PATH}."
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert "hardcoded_key" in data, "Missing 'hardcoded_key' in the JSON report."
    assert data["hardcoded_key"] == "BACKUP_9xQ2_fA11", f"Incorrect hardcoded_key. Expected 'BACKUP_9xQ2_fA11', got '{data['hardcoded_key']}'"

    assert "vulnerable_function" in data, "Missing 'vulnerable_function' in the JSON report."
    assert data["vulnerable_function"] == "read_token_file", f"Incorrect vulnerable_function. Expected 'read_token_file', got '{data['vulnerable_function']}'"

    assert "malicious_ips" in data, "Missing 'malicious_ips' in the JSON report."
    assert isinstance(data["malicious_ips"], list), "'malicious_ips' should be a list."

    expected_ips = ["10.0.5.55", "172.16.0.4"]
    actual_ips = data["malicious_ips"]
    assert sorted(actual_ips) == expected_ips, f"Incorrect malicious_ips. Expected {expected_ips}, got {actual_ips}"
    assert actual_ips == expected_ips, f"malicious_ips list is not sorted alphabetically/numerically as strings. Expected {expected_ips}, got {actual_ips}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
