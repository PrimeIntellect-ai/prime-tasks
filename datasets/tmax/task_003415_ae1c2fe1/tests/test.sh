#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hmac
import hashlib
import pytest

def decode_b64url(s):
    s += '=' * (-len(s) % 4)
    return base64.urlsafe_b64decode(s.replace('-', '+').replace('_', '/'))

def verify_jwt(token, secret):
    parts = token.split('.')
    if len(parts) != 3:
        return False, None
    header_b64, payload_b64, signature_b64 = parts

    try:
        header = json.loads(decode_b64url(header_b64).decode('utf-8'))
        payload = json.loads(decode_b64url(payload_b64).decode('utf-8'))
    except Exception:
        return False, None

    if header.get('alg') != 'HS256':
        return False, payload

    msg = f"{header_b64}.{payload_b64}".encode('utf-8')
    expected_sig = hmac.new(secret.encode('utf-8'), msg, hashlib.sha256).digest()
    expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode('utf-8').rstrip('=')

    if signature_b64 != expected_sig_b64:
        return False, payload

    return True, payload

def test_rotation_report():
    report_path = "/home/user/rotation_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert "SUCCESS: alpha" in lines, "Report is missing 'SUCCESS: alpha'."
    assert "TAMPERED: beta" in lines, "Report is missing 'TAMPERED: beta'."
    assert len(lines) == 2, f"Report should contain exactly 2 lines, found {len(lines)}."

def test_alpha_config_updated():
    alpha_path = "/home/user/configs/alpha.json"
    assert os.path.isfile(alpha_path), f"{alpha_path} is missing."

    with open(alpha_path, "r") as f:
        alpha_data = json.load(f)

    assert alpha_data.get("service") == "alpha", "alpha.json 'service' key was modified."
    assert alpha_data.get("port") == 8080, "alpha.json 'port' key was modified."

    token = alpha_data.get("token")
    assert token != "old-leaked-token-alpha", "alpha.json token was not rotated."

    with open("/home/user/master.key", "r") as f:
        master_key = f.read().strip()

    is_valid, payload = verify_jwt(token, master_key)
    assert is_valid, "alpha.json token is not a valid JWT signed with the master key."
    assert payload == {"service": "alpha", "version": 2}, "JWT payload in alpha.json is incorrect."

def test_beta_config_untampered_by_script():
    beta_path = "/home/user/configs/beta.json"
    assert os.path.isfile(beta_path), f"{beta_path} is missing."

    with open(beta_path, "r") as f:
        beta_data = json.load(f)

    assert beta_data.get("token") == "old-leaked-token-beta", "beta.json token should not be rotated because it was tampered."
    assert beta_data.get("malicious_injection") is True, "beta.json malicious injection was removed."

def test_gamma_config_untouched():
    gamma_path = "/home/user/configs/gamma.json"
    assert os.path.isfile(gamma_path), f"{gamma_path} is missing."

    with open(gamma_path, "r") as f:
        gamma_data = json.load(f)

    assert gamma_data.get("token") == "valid-token-gamma", "gamma.json token should not be rotated because it was not leaked."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
