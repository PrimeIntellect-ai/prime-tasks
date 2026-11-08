#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hmac
import hashlib
import subprocess


def test_admin_token():
    secret_path = "/home/user/keys/secret.key"
    token_path = "/home/user/admin_token.txt"

    assert os.path.exists(secret_path), f"Secret key file missing: {secret_path}"
    assert os.path.exists(token_path), f"Admin token file missing: {token_path}"

    with open(secret_path, "rb") as f:
        key = f.read()

    expected_hmac = hmac.new(key, b"admin-access-request", hashlib.sha256).hexdigest()

    with open(token_path, "r") as f:
        actual_hmac = f.read().strip()

    assert actual_hmac == expected_hmac, f"The token in {token_path} does not match the expected HMAC-SHA256 signature."


def test_ssh_hardening():
    priv_key = "/home/user/.ssh/ops_key"
    pub_key = "/home/user/.ssh/ops_key.pub"
    auth_keys = "/home/user/.ssh/authorized_keys"

    assert os.path.exists(priv_key), f"Private key missing: {priv_key}"
    assert os.path.exists(pub_key), f"Public key missing: {pub_key}"
    assert os.path.exists(auth_keys), f"Authorized keys file missing: {auth_keys}"
    assert os.path.isfile(priv_key), f"Private key is not a regular file: {priv_key}"
    assert os.path.isfile(pub_key), f"Public key is not a regular file: {pub_key}"

    with open(pub_key, "r") as f:
        pub_content = f.read().strip()

    pub_lines = pub_content.splitlines()
    assert len(pub_lines) == 1, "The public key file must contain exactly one public key entry."
    pub_fields = pub_lines[0].split()
    assert len(pub_fields) >= 2, "The public key file is not a valid SSH public key entry."
    assert pub_fields[0] == "ssh-ed25519", "The operations public key is not Ed25519."

    # Parse and validate the public key using OpenSSH.
    parsed = subprocess.run(
        ["ssh-keygen", "-l", "-f", pub_key],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert parsed.returncode == 0, f"Invalid SSH public key: {parsed.stderr.strip()}"
    assert parsed.stdout.rstrip().endswith("(ED25519)"), "The parsed public key is not Ed25519."

    # Derive the public key from the submitted private key. This also verifies that
    # the private key is readable without a passphrase and is a valid SSH key.
    derived = subprocess.run(
        ["ssh-keygen", "-y", "-f", priv_key],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert derived.returncode == 0, \
        f"Private key is invalid or requires a passphrase: {derived.stderr.strip()}"
    derived_fields = derived.stdout.strip().split()
    assert len(derived_fields) >= 2, "Could not derive a valid public key from the private key."
    assert derived_fields[0] == "ssh-ed25519", "The private key is not Ed25519."
    assert derived_fields[:2] == pub_fields[:2], \
        "The public key does not correspond to the private key."

    # The public key usually contains 'ssh-ed25519 <base64> [comment]'
    # Ensure the exact restriction string is prepended.
    expected_entry = f'restrict,from="10.0.0.0/8" {pub_content}'

    with open(auth_keys, "r") as f:
        auth_content = f.read().splitlines()

    assert any(expected_entry == line.strip() for line in auth_content), \
        f"The authorized_keys file does not contain the correctly restricted public key entry."


def test_header_audit():
    log_path = "/home/user/header_audit.log"

    assert os.path.exists(log_path), f"Audit log missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}"

    expected_lines = {
        "MISSING: X-Frame-Options",
        "MISSING: Strict-Transport-Security"
    }

    actual_lines = set(lines)
    assert actual_lines == expected_lines, \
        f"Audit log contents do not match expected. Expected: {expected_lines}, Found: {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
