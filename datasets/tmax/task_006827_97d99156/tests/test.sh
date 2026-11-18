#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import base64
import json
import hmac
import hashlib
import subprocess
import pytest

EXPECTED_CN = "CORRECT_SECRET_999XYZ"
EXPECTED_ORIGINAL_LOG = """2023-10-01 12:00:00 INFO Service started
2023-10-01 12:05:00 DEBUG Using secret SUPER_SECRET_LEGACY_V1 for signing
2023-10-01 12:10:00 ERROR Failed validation for token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
2023-10-01 12:15:00 INFO User logged in with legacy secret SUPER_SECRET_LEGACY_V1
2023-10-01 12:20:00 DEBUG Processed request with eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.another_fake_sig
"""


def get_valid_cert_cn():
    certs_dir = "/home/user/certs"
    ca_cert = os.path.join(certs_dir, "ca.crt")
    int_cert = os.path.join(certs_dir, "intermediate.crt")

    valid_cert = None
    for i in range(1, 4):
        cand_cert = os.path.join(certs_dir, f"candidate_{i}.crt")
        if not os.path.exists(cand_cert):
            continue

        cmd = [
            "openssl", "verify",
            "-CAfile", ca_cert,
            "-untrusted", int_cert,
            cand_cert,
        ]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0 and "OK" in result.stdout:
            valid_cert = cand_cert
            break

    assert valid_cert is not None, "Could not find a valid candidate certificate in the chain."

    cmd = ["openssl", "x509", "-noout", "-subject", "-in", valid_cert]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"Failed to read subject from {valid_cert}"

    match = re.search(r'CN\s*=\s*([^,\n]+)', result.stdout)
    assert match is not None, f"Could not extract CN from {valid_cert} subject: {result.stdout}"

    return match.group(1).strip()


def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str)


def test_jwt_generation():
    token_path = "/home/user/new_token.txt"
    assert os.path.isfile(token_path), f"The token file {token_path} is missing."

    with open(token_path, "r") as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, "The token does not have 3 parts (header, payload, signature)."

    header_b64, payload_b64, signature_b64 = parts

    try:
        header = json.loads(base64url_decode(header_b64).decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT header: {e}")

    assert header == {"alg": "HS256", "typ": "JWT"}, f"JWT header mismatch. Got: {header}"

    try:
        payload = json.loads(base64url_decode(payload_b64).decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT payload: {e}")

    expected_payload = {"service": "backend", "role": "admin", "exp": 1893456000}
    assert payload == expected_payload, f"JWT payload mismatch. Got: {payload}"

    secret = get_valid_cert_cn()
    assert secret == EXPECTED_CN, "The certificate inputs no longer identify the original valid certificate CN."

    msg = f"{header_b64}.{payload_b64}".encode('utf-8')
    expected_sig = base64.urlsafe_b64encode(
        hmac.new(secret.encode('utf-8'), msg, hashlib.sha256).digest()
    ).replace(b'=', b'').decode('utf-8')

    assert signature_b64 == expected_sig, "JWT signature is invalid or not signed with the correct CN."

    fixed_expected_sig = base64.urlsafe_b64encode(
        hmac.new(EXPECTED_CN.encode('utf-8'), msg, hashlib.sha256).digest()
    ).rstrip(b'=').decode('utf-8')
    assert signature_b64 == fixed_expected_sig, "JWT was not signed with the CN from the original certificate chain."


def test_log_redaction():
    original_log_path = "/home/user/app/service.log"
    redacted_log_path = "/home/user/app/service_redacted.log"

    assert os.path.isfile(original_log_path), f"Original log file {original_log_path} is missing."
    assert os.path.isfile(redacted_log_path), f"Redacted log file {redacted_log_path} is missing."

    with open(original_log_path, "r") as f:
        original_text = f.read()
    assert original_text == EXPECTED_ORIGINAL_LOG, "The source service log was modified."

    original_lines = original_text.splitlines(keepends=True)
    with open(redacted_log_path, "r") as f:
        redacted_lines = f.readlines()

    assert len(original_lines) == len(redacted_lines), "Redacted log does not have the same number of lines as the original."

    jwt_pattern = re.compile(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')

    for i, (orig, red) in enumerate(zip(original_lines, redacted_lines)):
        expected_line = orig.replace("SUPER_SECRET_LEGACY_V1", "[REDACTED_SECRET]")
        expected_line = jwt_pattern.sub("[REDACTED_TOKEN]", expected_line)
        assert red == expected_line, f"Line {i+1} in redacted log is incorrect.\nExpected: {expected_line}\nGot: {red}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
