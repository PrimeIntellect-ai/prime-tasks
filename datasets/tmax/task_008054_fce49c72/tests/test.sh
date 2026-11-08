#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import base64
import hashlib
import pytest

def b64url_nopad(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode('utf-8')

def test_forged_admin_token():
    token_path = "/home/user/new_admin_token.txt"
    assert os.path.exists(token_path), f"Forged token file {token_path} is missing."
    assert os.path.isfile(token_path), f"Path {token_path} is not a file."

    with open(token_path, "r") as f:
        actual_token = f.read().strip()

    assert actual_token, f"The file {token_path} is empty."

    # Compute expected token
    header_str = '{"alg":"md5","typ":"cJWT"}'
    payload_str = '{"user":"admin","action":"rotate_credentials"}'
    secret = "mango"

    h = b64url_nopad(header_str.encode())
    p = b64url_nopad(payload_str.encode())
    sig_input = f"{h}.{p}.{secret}".encode()
    sig = hashlib.md5(sig_input).hexdigest()
    expected_token = f"{h}.{p}.{sig}"

    assert actual_token == expected_token, f"The forged token in {token_path} does not match the expected value."

def test_redacted_server_logs():
    original_logs_path = "/home/user/server_logs.txt"
    redacted_logs_path = "/home/user/server_logs_redacted.txt"

    assert os.path.exists(original_logs_path), f"Original logs file {original_logs_path} is missing."
    assert os.path.exists(redacted_logs_path), f"Redacted logs file {redacted_logs_path} is missing."
    assert os.path.isfile(redacted_logs_path), f"Path {redacted_logs_path} is not a file."

    with open(original_logs_path, "r") as f:
        original_logs = f.read()

    with open(redacted_logs_path, "r") as f:
        actual_redacted_logs = f.read()

    # Generate expected redacted logs dynamically
    # The custom JWT format is Header.Payload.Signature where Signature is a 32-char MD5 hex string
    # Header and Payload are base64url encoded.
    jwt_pattern = r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[a-fA-F0-9]{32}'
    expected_redacted_logs = re.sub(jwt_pattern, "[REDACTED]", original_logs)

    assert actual_redacted_logs == expected_redacted_logs, (
        f"The content of {redacted_logs_path} does not match the expected redacted output. "
        "Ensure only the tokens are replaced with '[REDACTED]' and the rest of the file is unchanged."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
