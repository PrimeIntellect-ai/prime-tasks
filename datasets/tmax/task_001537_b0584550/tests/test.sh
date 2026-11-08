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
    assert os.path.isfile(REPORT_PATH), f"Audit report file not found at {REPORT_PATH}"

def test_audit_report_valid_json():
    with open(REPORT_PATH, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Audit report is not valid JSON: {e}")

def test_audit_report_contents():
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    # Check service port
    assert "service_port" in data, "Key 'service_port' missing in audit report"
    assert data["service_port"] == 8443, f"Expected service_port to be 8443, got {data['service_port']}"

    # Check world writable files
    assert "world_writable_files" in data, "Key 'world_writable_files' missing in audit report"
    expected_files = ["/home/user/audit_target/users.db"]
    assert isinstance(data["world_writable_files"], list), "'world_writable_files' must be a list"
    assert sorted(data["world_writable_files"]) == sorted(expected_files), \
        f"Expected world_writable_files to be {expected_files}, got {data['world_writable_files']}"

    # Check SQLi line number
    assert "sqli_line_number" in data, "Key 'sqli_line_number' missing in audit report"
    assert data["sqli_line_number"] == 19, f"Expected sqli_line_number to be 19, got {data['sqli_line_number']}"

    # Check XSS line number
    assert "xss_line_number" in data, "Key 'xss_line_number' missing in audit report"
    assert data["xss_line_number"] == 30, f"Expected xss_line_number to be 30, got {data['xss_line_number']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
