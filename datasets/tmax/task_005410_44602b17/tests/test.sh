#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import base64
import pytest
from datetime import datetime

REPORT_PATH = "/home/user/audit_report.json"
API_LOG_PATH = "/home/user/logs/api_traffic.log"
EVENTS_LOG_PATH = "/home/user/logs/privilege_events.json"

def get_expected_jwt_data():
    """Derives the attacker IP and XSS payload from the API logs."""
    with open(API_LOG_PATH, 'r') as f:
        for line in f:
            # Look for the alg: none JWT header in base64url (eyJhbGciOiJub25l)
            if "eyJhbGciOiJub25l" in line:
                parts = line.split()
                ip = parts[0]

                # Extract the Bearer token
                auth_header_idx = line.find("Bearer ")
                if auth_header_idx != -1:
                    token = line[auth_header_idx + 7:].split('"')[0].strip()
                    token_parts = token.split('.')
                    if len(token_parts) >= 2:
                        payload_b64 = token_parts[1]
                        # Add padding if necessary
                        payload_b64 += "=" * ((4 - len(payload_b64) % 4) % 4)
                        payload_json = base64.urlsafe_b64decode(payload_b64).decode('utf-8')
                        payload_data = json.loads(payload_json)
                        return ip, payload_data.get("profile_data")
    return None, None

def get_expected_escalated_user():
    """Derives the escalated user from the privilege events log."""
    with open(EVENTS_LOG_PATH, 'r') as f:
        events = json.load(f)
        for event in events:
            if event.get("role") == "SuperAdmin":
                return event.get("target_user")
    return None

def test_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The final audit report is missing at {REPORT_PATH}."

def test_audit_report_is_valid_json():
    with open(REPORT_PATH, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file at {REPORT_PATH} is not valid JSON.")

def test_audit_report_contents():
    with open(REPORT_PATH, 'r') as f:
        report = json.load(f)

    expected_ip, expected_xss = get_expected_jwt_data()
    expected_user = get_expected_escalated_user()

    # The certificate CN is hard to parse with pure stdlib without external tools, 
    # but based on the setup truth, it is known to be WAF-Intermediate-Node-7.
    expected_cert_cn = "WAF-Intermediate-Node-7"

    assert "expired_cert_cn" in report, "Missing 'expired_cert_cn' in the audit report."
    assert report["expired_cert_cn"] == expected_cert_cn, \
        f"Incorrect expired_cert_cn. Expected '{expected_cert_cn}', got '{report['expired_cert_cn']}'."

    assert "attacker_ip" in report, "Missing 'attacker_ip' in the audit report."
    assert report["attacker_ip"] == expected_ip, \
        f"Incorrect attacker_ip. Expected '{expected_ip}', got '{report['attacker_ip']}'."

    assert "xss_payload" in report, "Missing 'xss_payload' in the audit report."
    assert report["xss_payload"] == expected_xss, \
        f"Incorrect xss_payload. Expected '{expected_xss}', got '{report['xss_payload']}'."

    assert "escalated_user" in report, "Missing 'escalated_user' in the audit report."
    assert report["escalated_user"] == expected_user, \
        f"Incorrect escalated_user. Expected '{expected_user}', got '{report['escalated_user']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
