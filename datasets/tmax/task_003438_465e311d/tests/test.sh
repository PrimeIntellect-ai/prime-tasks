#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import pytest

REPORT_PATH = "/home/user/audit_report.json"

def test_audit_report_exists():
    """Verify that the audit report file exists."""
    assert os.path.exists(REPORT_PATH), f"Audit report missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file."

def test_audit_report_permissions():
    """Verify that the audit report has exactly 0400 permissions."""
    st = os.stat(REPORT_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"File permissions are {oct(perms)}, expected 0o400."

def test_audit_report_content():
    """Verify the content of the audit report matches expected JSON values."""
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit report is not valid JSON.")

    expected_cookie = "malicious_token_8891"
    expected_password = "winter2024"
    expected_cn = "Internal-Root-CA"

    assert "sqli_session_cookie" in data, "Missing 'sqli_session_cookie' in audit report."
    assert data["sqli_session_cookie"] == expected_cookie, \
        f"Expected sqli_session_cookie to be '{expected_cookie}', got '{data['sqli_session_cookie']}'"

    assert "admin_password" in data, "Missing 'admin_password' in audit report."
    assert data["admin_password"] == expected_password, \
        f"Expected admin_password to be '{expected_password}', got '{data['admin_password']}'"

    assert "cert_issuer_cn" in data, "Missing 'cert_issuer_cn' in audit report."
    assert data["cert_issuer_cn"] == expected_cn, \
        f"Expected cert_issuer_cn to be '{expected_cn}', got '{data['cert_issuer_cn']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
