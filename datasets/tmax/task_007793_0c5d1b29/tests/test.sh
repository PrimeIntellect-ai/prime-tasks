#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import hashlib
import pytest

def test_encrypted_file_exists():
    enc_path = "/home/user/payload_obfuscated.enc"
    assert os.path.exists(enc_path), f"Encrypted file missing: {enc_path}"
    assert os.path.isfile(enc_path), f"Expected a file at {enc_path}"

def test_integrity_file():
    enc_path = "/home/user/payload_obfuscated.enc"
    hash_path = "/home/user/integrity.sha256"

    assert os.path.exists(hash_path), f"Integrity file missing: {hash_path}"

    # Calculate actual SHA256 of the encrypted file
    sha256_hash = hashlib.sha256()
    with open(enc_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    actual_hash = sha256_hash.hexdigest()

    # Read the integrity file
    with open(hash_path, "r") as f:
        hash_content = f.read().strip()

    # The format should be standard sha256sum, e.g. "hash  /home/user/payload_obfuscated.enc" or similar
    # We just check if the actual hash is in the file
    assert actual_hash in hash_content, f"The SHA-256 hash in {hash_path} does not match the actual hash of {enc_path}."

def test_decryption_and_redaction():
    enc_path = "/home/user/payload_obfuscated.enc"

    # Decrypt using OpenSSL
    cmd = [
        "openssl", "aes-256-cbc", "-d", "-pbkdf2",
        "-in", enc_path,
        "-pass", "pass:Evasion123"
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        decrypted_content = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to decrypt {enc_path}. Ensure it was encrypted with aes-256-cbc, pbkdf2, and the correct password. Error: {e.stderr}")

    expected_content = (
        '#!/bin/bash\n'
        'REDACTED_1="192.168.1.100"\n'
        'REDACTED_2="http://malicious.com/drop"\n'
        'echo "Dumping to $REDACTED_2 from $REDACTED_1"\n'
        '/opt/tools/REDACTED_3\n'
    )

    assert decrypted_content == expected_content, "The decrypted content does not match the expected redacted payload exactly."

def test_no_intermediate_files():
    # Check that there are no unencrypted redacted files left in /home/user/
    allowed_files = {"payload.txt", "payload_obfuscated.enc", "integrity.sha256", ".bash_history", ".bashrc", ".profile", ".bash_logout"}

    for filename in os.listdir("/home/user"):
        filepath = os.path.join("/home/user", filename)
        if os.path.isfile(filepath) and filename not in allowed_files and not filename.startswith('.'):
            # If there's an extra file, check if it contains REDACTED
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                    if "REDACTED_1" in content or "REDACTED_2" in content or "REDACTED_3" in content:
                        pytest.fail(f"Found intermediate unencrypted redacted file: {filepath}")
            except Exception:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
