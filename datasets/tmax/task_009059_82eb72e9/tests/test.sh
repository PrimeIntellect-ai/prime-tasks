#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import base64
import hashlib
import re
import pytest

def decrypt_token(token):
    key = "COMPLIANCE"
    try:
        decoded = base64.b64decode(token)
        decrypted = bytearray()
        for i, byte in enumerate(decoded):
            decrypted.append(byte ^ ord(key[i % len(key)]))
        return decrypted.decode('utf-8')
    except Exception:
        return ""

def test_redirects_file():
    log_path = "/home/user/access.log"
    redirects_path = "/home/user/redirects.txt"

    assert os.path.exists(log_path), f"Log file {log_path} is missing."
    assert os.path.exists(redirects_path), f"Output file {redirects_path} is missing."

    expected_redirects = []
    with open(log_path, 'r') as f:
        for line in f:
            match = re.search(r'token=([^&\s]+)', line)
            if match:
                token = match.group(1)
                decrypted = decrypt_token(token)
                if decrypted.startswith("http://") or decrypted.startswith("https://"):
                    expected_redirects.append(decrypted)

    with open(redirects_path, 'r') as f:
        actual_redirects = [line.strip() for line in f if line.strip()]

    assert actual_redirects == expected_redirects, "The extracted open redirects do not match the expected ones."

def test_audit_checksum_file():
    redirects_path = "/home/user/redirects.txt"
    checksum_path = "/home/user/audit_checksum.txt"

    assert os.path.exists(redirects_path), f"Output file {redirects_path} is missing."
    assert os.path.exists(checksum_path), f"Checksum file {checksum_path} is missing."

    with open(redirects_path, 'rb') as f:
        content = f.read()
        expected_hash = hashlib.sha256(content).hexdigest()

    with open(checksum_path, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"The checksum in {checksum_path} does not match the actual SHA-256 hash of {redirects_path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
