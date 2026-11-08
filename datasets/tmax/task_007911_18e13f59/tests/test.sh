#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import base64
import pytest

def get_cert_pubkey(cert_path):
    """Extracts the public key from a certificate using openssl."""
    result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def get_rsa_pubkey(privkey_path):
    """Extracts the public key from an RSA private key using openssl."""
    result = subprocess.run(
        ["openssl", "rsa", "-in", privkey_path, "-pubout"],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

def find_matching_key():
    """Dynamically finds which SSH key matches the server certificate."""
    cert_pubkey = get_cert_pubkey("/home/user/investigation/server.crt")
    ssh_keys_dir = "/home/user/investigation/ssh_keys"

    for key_name in ["id_rsa_A", "id_rsa_B", "id_rsa_C"]:
        key_path = os.path.join(ssh_keys_dir, key_name)
        if os.path.isfile(key_path):
            try:
                if get_rsa_pubkey(key_path) == cert_pubkey:
                    return key_name, key_path
            except subprocess.CalledProcessError:
                continue
    return None, None

def test_cert_status_file():
    status_file = "/home/user/cert_status.txt"
    assert os.path.isfile(status_file), f"{status_file} is missing."

    with open(status_file, "r") as f:
        content = f.read().strip()

    assert "server.crt: OK" in content, f"Expected 'server.crt: OK' in {status_file}, but found: {content}"

def test_matched_key_file():
    matched_file = "/home/user/matched_key.txt"
    assert os.path.isfile(matched_file), f"{matched_file} is missing."

    expected_key_name, _ = find_matching_key()
    assert expected_key_name is not None, "Could not dynamically determine the matching key from the environment."

    with open(matched_file, "r") as f:
        content = f.read().strip()

    assert content == expected_key_name, f"Expected {matched_file} to contain '{expected_key_name}', but found '{content}'."

def test_payload_file():
    payload_file = "/home/user/payload.txt"
    assert os.path.isfile(payload_file), f"{payload_file} is missing."

    _, expected_key_path = find_matching_key()
    assert expected_key_path is not None, "Could not dynamically determine the matching key to verify payload."

    # Generate the expected signature dynamically
    payload_text = b"user=admin&action=shell"

    # Use openssl dgst to sign the payload
    process = subprocess.Popen(
        ["openssl", "dgst", "-sha256", "-sign", expected_key_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    stdout, stderr = process.communicate(input=payload_text)
    assert process.returncode == 0, f"Failed to generate expected signature: {stderr.decode()}"

    expected_base64 = base64.b64encode(stdout).decode('utf-8')
    expected_header = f"X-Auth-Signature: {expected_base64}"

    with open(payload_file, "r") as f:
        content = f.read().strip()

    assert content == expected_header, f"Payload file content does not match the expected signed header format or signature."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
