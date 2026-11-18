#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -rf /root/verifier_tests
mkdir -m 700 /root/verifier_tests

cat << 'TEST_EOF' > /root/verifier_tests/test_final_state.py
import base64
import os
import stat
import subprocess

import pytest
from Crypto.Cipher import AES

EXPECTED_SCRIPT = b'''#!/usr/bin/env python3
import sys
import base64
import json
from Crypto.Cipher import AES

KEY = b"RedTeamEvasion99"

def verify(token_path):
    try:
        with open(token_path, 'r') as f:
            token = f.read().strip()

        cipher = AES.new(KEY, AES.MODE_ECB)
        # Decrypts without unpadding to avoid padding errors for this scenario
        decrypted_bytes = cipher.decrypt(base64.b64decode(token))
        decrypted_str = decrypted_bytes.strip(b'\\x00').decode('utf-8')

        data = json.loads(decrypted_str)

        if data.get("role") == "admin" and data.get("user") == "system":
            print("Authentication Bypass Successful")
            with open("/home/user/success.log", "w") as f:
                f.write("Bypassed")
        else:
            print("Authentication Failed: Insufficient privileges")
    except Exception as e:
        print(f"Error processing token: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: verify.py <token_file>")
        sys.exit(1)
    verify(sys.argv[1])
'''


def test_target_integrity():
    """Verify that the supplied authentication script was not modified or replaced."""
    script_path = "/home/user/auth_verifier.py"
    assert os.path.lexists(script_path), f"Target script {script_path} is missing."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), (
        f"Target script {script_path} must be the original regular file."
    )
    with open(script_path, "rb") as f:
        actual = f.read()
    assert actual == EXPECTED_SCRIPT, (
        f"Target script {script_path} was modified. The task explicitly forbids modifying it."
    )


def test_cwe_identification():
    """Verify that the student correctly identified the CWE."""
    cwe_path = "/home/user/cwe.txt"
    assert os.path.exists(cwe_path), f"Required file {cwe_path} is missing. You must write the CWE identifier to this file."

    with open(cwe_path, "r") as f:
        content = f.read().upper()

    assert "CWE-798" in content or "CWE-327" in content, (
        f"The file {cwe_path} does not contain the correct CWE identifier. "
        "Expected CWE-798 (Use of Hard-coded Credentials) or CWE-327."
    )
    assert content.strip() in {"CWE-798", "CWE-327"}, (
        f"The file {cwe_path} must contain only the exact CWE identifier."
    )


def test_payload_format():
    """Verify that the payload file exists and contains valid base64."""
    payload_path = "/home/user/payload.txt"
    assert os.path.exists(payload_path), f"Required file {payload_path} is missing."

    with open(payload_path, "r") as f:
        content = f.read().strip()

    assert len(content) > 0, f"The file {payload_path} is empty."

    try:
        ciphertext = base64.b64decode(content, validate=True)
    except Exception as e:
        pytest.fail(f"The content of {payload_path} is not valid base64: {e}")

    assert len(ciphertext) > 0 and len(ciphertext) % AES.block_size == 0, (
        "The decoded payload must be non-empty AES block-aligned ciphertext."
    )
    plaintext = AES.new(b"RedTeamEvasion99", AES.MODE_ECB).decrypt(ciphertext)
    assert plaintext == b'{"role":"admin","user":"system"}', (
        "The payload does not decrypt under the target key to the required exact JSON token."
    )


def test_authentication_bypass():
    """Verify that the crafted payload successfully bypasses the authentication script."""
    script_path = "/home/user/auth_verifier.py"
    payload_path = "/home/user/payload.txt"
    success_log_path = "/home/user/success.log"

    assert os.path.exists(script_path), f"Target script {script_path} is missing."
    assert os.path.exists(payload_path), f"Payload file {payload_path} is missing."

    if os.path.exists(success_log_path) or os.path.islink(success_log_path):
        os.remove(success_log_path)

    result = subprocess.run(
        ["python3", script_path, payload_path],
        capture_output=True,
        text=True,
        timeout=10,
        cwd="/root/verifier_tests",
    )

    assert result.returncode == 0, (
        f"Authentication script exited with status {result.returncode}.\n"
        f"Script stdout: {result.stdout.strip()}\n"
        f"Script stderr: {result.stderr.strip()}"
    )
    assert os.path.exists(success_log_path), (
        f"Authentication bypass failed. The file {success_log_path} was not created.\n"
        f"Script stdout: {result.stdout.strip()}\n"
        f"Script stderr: {result.stderr.strip()}"
    )

    with open(success_log_path, "r") as f:
        log_content = f.read().strip()

    assert log_content == "Bypassed", (
        f"Authentication bypass failed. Expected '{success_log_path}' to contain 'Bypassed', "
        f"but found '{log_content}'."
    )
TEST_EOF

if cd /root/verifier_tests && PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
