#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import base64
import subprocess
from datetime import datetime
import re
import pytest

def decode_base64url(data):
    # Add padding if necessary
    rem = len(data) % 4
    if rem > 0:
        data += '=' * (4 - rem)
    return base64.urlsafe_b64decode(data).decode('utf-8')

def test_forged_token():
    path = "/home/user/forged_token.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, "Forged token must have 3 parts separated by dots"

    header_b64, payload_b64, signature = parts
    assert signature == "", "Signature part of the forged token must be empty"

    try:
        header = json.loads(decode_base64url(header_b64))
    except Exception as e:
        pytest.fail(f"Failed to decode header: {e}")

    assert header.get("alg", "").lower() == "none", "Token header 'alg' must be 'none'"

    try:
        payload = json.loads(decode_base64url(payload_b64))
    except Exception as e:
        pytest.fail(f"Failed to decode payload: {e}")

    assert payload.get("username") == "guest_user", "Token payload 'username' must be 'guest_user'"
    assert payload.get("role") == "admin", "Token payload 'role' must be 'admin'"

def test_cert_report():
    path = "/home/user/cert_report.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 2, "cert_report.txt must contain exactly 2 lines"

    # Extract actual expiration from the cert to compare
    cert_path = "/home/user/server.crt"
    assert os.path.isfile(cert_path), f"Missing cert file: {cert_path}"

    try:
        enddate_output = subprocess.check_output(
            ["openssl", "x509", "-in", cert_path, "-noout", "-enddate"],
            text=True
        ).strip()
        # enddate_output format: notAfter=Oct  1 10:00:01 2033 GMT
        date_str = enddate_output.split("=", 1)[1]
        dt = datetime.strptime(date_str, "%b %d %H:%M:%S %Y %Z")
        expected_date = dt.strftime("%Y-%m-%d")
    except Exception as e:
        pytest.fail(f"Failed to read certificate expiration: {e}")

    assert lines[0].startswith("Expiration: "), "First line must start with 'Expiration: '"
    reported_date = lines[0].split(":", 1)[1].strip()
    assert reported_date == expected_date, f"Expected expiration {expected_date}, got {reported_date}"

    assert lines[1].startswith("SANs: "), "Second line must start with 'SANs: '"
    reported_sans = lines[1].split(":", 1)[1].strip()
    sans_list = [s.strip() for s in reported_sans.split(",")]
    expected_sans = ["auth.internal.corp", "backup.internal.corp"]
    assert set(sans_list) == set(expected_sans), f"Expected SANs {expected_sans}, got {sans_list}"

def test_api_key():
    path = "/home/user/api_key.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        key = f.read().strip()

    assert key == "xK9#mP2$vL", "api_key.txt does not contain the correct API key"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
