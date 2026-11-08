#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import base64
import subprocess
import pytest

def test_ssh_permissions():
    """Verify that the SSH directory and legacy private key have strict permissions."""
    ssh_dir = "/home/user/.ssh"
    id_rsa = "/home/user/.ssh/id_rsa"

    assert os.path.isdir(ssh_dir), f"Directory {ssh_dir} does not exist."
    dir_mode = stat.S_IMODE(os.stat(ssh_dir).st_mode)
    assert dir_mode == 0o700, f"Permissions for {ssh_dir} should be 700, but are {oct(dir_mode)}."

    assert os.path.isfile(id_rsa), f"File {id_rsa} does not exist."
    file_mode = stat.S_IMODE(os.stat(id_rsa).st_mode)
    assert file_mode == 0o600, f"Permissions for {id_rsa} should be 600, but are {oct(file_mode)}."

def test_deploy_key_generated():
    """Verify that the new ed25519 deploy key pair exists and is valid."""
    priv_key_path = "/home/user/.ssh/deploy_key"
    pub_key_path = "/home/user/.ssh/deploy_key.pub"

    assert os.path.isfile(priv_key_path), f"Private key {priv_key_path} was not created."
    assert os.path.isfile(pub_key_path), f"Public key {pub_key_path} was not created."

    with open(priv_key_path, "r") as f:
        priv_content = f.read()

    assert "OPENSSH PRIVATE KEY" in priv_content, f"{priv_key_path} does not appear to be a valid OpenSSH private key."
    # ed25519 keys use the new OpenSSH format

    # Derive the public key from the private key using an empty passphrase. This
    # proves the private key is parseable and unencrypted, and lets us verify the pair.
    result = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", priv_key_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"{priv_key_path} is not a valid unencrypted SSH private key: {result.stderr.strip()}"

    derived_fields = result.stdout.strip().split()
    assert len(derived_fields) >= 2, "Could not derive a public key from the deploy private key."
    assert derived_fields[0] == "ssh-ed25519", "The deploy private key is not an Ed25519 key."

    with open(pub_key_path, "r") as f:
        pub_content = f.read().strip()
    pub_fields = pub_content.split()
    assert len(pub_fields) >= 2, f"{pub_key_path} is not a valid SSH public key."
    assert pub_fields[0] == "ssh-ed25519", "The deploy public key is not an Ed25519 key."
    assert pub_fields[:2] == derived_fields[:2], "The deploy public key does not match the deploy private key."

    pub_check = subprocess.run(
        ["ssh-keygen", "-l", "-f", pub_key_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert pub_check.returncode == 0, f"{pub_key_path} is not a valid SSH public key: {pub_check.stderr.strip()}"

def test_rotation_summary_contents():
    """Verify the contents of the rotation summary report using derived expectations."""
    summary_path = "/home/user/rotation_summary.txt"
    payload_path = "/home/user/admin_payload.b64"
    pub_key_path = "/home/user/.ssh/deploy_key.pub"

    assert os.path.isfile(summary_path), f"Report file {summary_path} was not created."

    with open(summary_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 3, f"{summary_path} must contain exactly 3 lines, found {len(lines)}."
    assert len(lines) == 3, f"{summary_path} must contain exactly 3 lines, found {len(lines)}."

    # Recompute expected Line 1 (Recovered password)
    assert os.path.isfile(payload_path), f"Original payload {payload_path} is missing."
    with open(payload_path, "r") as f:
        b64_payload = f.read().strip()

    decoded_bytes = base64.b64decode(b64_payload)
    decrypted_str = "".join(chr(b ^ 0x3F) for b in decoded_bytes)

    assert ":" in decrypted_str, "Decrypted payload does not contain a colon separator."
    expected_password = decrypted_str.split(":", 1)[1]

    assert lines[0] == expected_password, "Line 1 of rotation summary does not match the recovered password."

    # Recompute expected Line 2 (Public key string)
    assert os.path.isfile(pub_key_path), f"Public key {pub_key_path} is missing."
    with open(pub_key_path, "r") as f:
        expected_pub_key = f.read().strip()

    assert lines[1] == expected_pub_key, "Line 2 of rotation summary does not match the generated public key."

    # Recompute expected Line 3 (New token for system_admin)
    target_user = "system_admin"
    expected_token_bytes = bytes([ord(c) ^ 0x3F for c in target_user])
    expected_token = base64.b64encode(expected_token_bytes).decode('utf-8')

    assert lines[2] == expected_token, "Line 3 of rotation summary does not match the correctly encoded token for system_admin."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
