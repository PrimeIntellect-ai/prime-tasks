#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import hashlib
import base64

def test_report_content():
    """Verify the report.txt contains the correct staging hostname, secret, and forged token."""
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) >= 3, "Report file must contain at least 3 lines."

    # 1. Extract staging hostname from certificate
    cert_path = "/home/user/api_audit/server.crt"
    cert_text = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-text", "-noout"], 
        capture_output=True, 
        text=True
    ).stdout

    staging_host = None
    for line in cert_text.split('\n'):
        if "DNS:" in line:
            parts = line.split(',')
            for part in parts:
                part = part.strip()
                if part.startswith("DNS:") and "staging" in part:
                    staging_host = part.split('DNS:')[1]
                    break
        if staging_host:
            break

    assert staging_host is not None, "Could not find staging hostname in certificate."

    # 2. Extract secret from traffic log
    log_path = "/home/user/api_audit/traffic.log"
    with open(log_path, "r") as f:
        log_content = f.read()

    requests = log_content.split("\n\n")
    secret = None
    for req in requests:
        if f"Host: {staging_host}" in req:
            for line in req.split('\n'):
                if line.startswith("X-Debug-Secret:"):
                    secret = line.split(":", 1)[1].strip()
                    break
            if secret:
                break

    assert secret is not None, "Could not find secret in traffic log."

    # 3. Compute expected forged token
    username = "admin"
    timestamp = "1800000000"
    string_to_hash = f"{username}|{timestamp}|{secret}"
    signature = hashlib.md5(string_to_hash.encode()).hexdigest()
    full_string = f"{username}|{timestamp}|{signature}"
    expected_token = base64.b64encode(full_string.encode()).decode()

    # 4. Assert against report.txt
    assert lines[0] == staging_host, f"Line 1 (Staging Hostname) is incorrect. Expected '{staging_host}', got '{lines[0]}'"
    assert lines[1] == secret, f"Line 2 (Secret) is incorrect. Expected '{secret}', got '{lines[1]}'"
    assert lines[2] == expected_token, f"Line 3 (Forged Token) is incorrect. Expected '{expected_token}', got '{lines[2]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
