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
    assert os.path.isfile(REPORT_PATH), f"The audit report file {REPORT_PATH} does not exist."

def test_audit_report_content():
    assert os.path.isfile(REPORT_PATH), f"The audit report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    expected_keys = {"csp_unsafe", "weak_token_cwe", "cert_subject_cn"}

    assert set(data.keys()) == expected_keys, f"The JSON report must contain exactly these keys: {expected_keys}. Found: {set(data.keys())}"

    assert data["csp_unsafe"] is True, "The 'csp_unsafe' value should be true (boolean)."
    assert data["weak_token_cwe"] == "CWE-338", "The 'weak_token_cwe' value should be 'CWE-338'."
    assert data["cert_subject_cn"] == "secure.internal.com", "The 'cert_subject_cn' value should be 'secure.internal.com'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
