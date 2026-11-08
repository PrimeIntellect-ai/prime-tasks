#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import base64
import hmac
import re

def get_expected_cert_fingerprint(cert_path):
    """Derives the SHA256 fingerprint of the certificate."""
    with open(cert_path, 'r') as f:
        pem_data = f.read()

    # Extract base64 content between BEGIN and END lines
    cert_b64 = "".join([line.strip() for line in pem_data.splitlines() if not line.startswith("-----")])
    der_data = base64.b64decode(cert_b64)

    sha256_hash = hashlib.sha256(der_data).hexdigest().upper()
    # Format as XX:XX:XX...
    fingerprint = ":".join(sha256_hash[i:i+2] for i in range(0, len(sha256_hash), 2))
    return fingerprint

def get_expected_log_data(log_path):
    """Parses the log to find the attacker IP and JWT for the successful path traversal."""
    ip = None
    token = None
    with open(log_path, 'r') as f:
        for line in f:
            # Look for path traversal (../) and 200 OK
            if "../" in line and " 200 " in line:
                parts = line.split()
                ip = parts[0]

                # Extract token from Authorization header
                auth_match = re.search(r'Authorization: Bearer ([a-zA-Z0-9_.-]+)', line)
                if auth_match:
                    token = auth_match.group(1)
                break
    return ip, token

def derive_jwt_secret(token, wordlist_path):
    """Brute-forces the JWT secret using the provided wordlist to find the expected truth."""
    if not token:
        return None

    parts = token.split('.')
    if len(parts) != 3:
        return None

    header_payload = f"{parts[0]}.{parts[1]}".encode('utf-8')
    expected_sig_b64 = parts[2]

    # Pad the base64 signature for decoding
    pad_len = 4 - (len(expected_sig_b64) % 4)
    expected_sig_b64 += "=" * pad_len

    with open(wordlist_path, 'r') as f:
        words = [line.strip() for line in f if line.strip()]

    for word in words:
        sig = hmac.new(word.encode('utf-8'), header_payload, hashlib.sha256).digest()
        # JWT uses base64url encoding without padding
        sig_b64 = base64.urlsafe_b64encode(sig).decode('utf-8').rstrip('=')
        if sig_b64 == parts[2]:
            return word
    return None

def test_incident_report_exists_and_valid():
    report_path = "/home/user/incident_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The incident report is not valid JSON.")

    required_keys = ["cert_fingerprint_sha256", "attacker_ip", "jwt_token", "jwt_secret_key"]
    for key in required_keys:
        assert key in report, f"Missing required key '{key}' in incident report."

def test_incident_report_content():
    report_path = "/home/user/incident_report.json"
    cert_path = "/home/user/evidence/rogue.crt"
    log_path = "/home/user/evidence/access.log"
    wordlist_path = "/home/user/evidence/wordlist.txt"

    with open(report_path, 'r') as f:
        report = json.load(f)

    expected_fingerprint = get_expected_cert_fingerprint(cert_path)
    expected_ip, expected_token = get_expected_log_data(log_path)
    expected_secret = derive_jwt_secret(expected_token, wordlist_path)

    assert report["cert_fingerprint_sha256"] == expected_fingerprint, "Certificate fingerprint does not match the expected SHA256 format."
    assert report["attacker_ip"] == expected_ip, "Attacker IP does not match the IP that performed the successful path traversal."
    assert report["jwt_token"] == expected_token, "JWT token does not match the token used in the attack."
    assert report["jwt_secret_key"] == expected_secret, "JWT secret key does not match the cracked secret."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
