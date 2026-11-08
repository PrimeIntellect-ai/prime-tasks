#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_audit_report_exists_and_valid():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"The audit report is missing at {report_path}."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_keys = {"admin_jti", "zip_pin", "decoded_payload"}
    assert set(data.keys()) == expected_keys, f"The JSON keys in {report_path} do not match the expected keys. Found: {list(data.keys())}"

    assert data["admin_jti"] == "auth-8472", "The admin_jti value is incorrect."
    assert data["zip_pin"] == "6291", "The zip_pin value is incorrect."
    assert data["decoded_payload"] == "EVIDENCE_FOUND_CRITICAL_SYSTEM_COMPROMISE", "The decoded_payload value is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
