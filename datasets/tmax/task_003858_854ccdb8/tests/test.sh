#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import pytest

ENC_FILE = "/home/user/compromised.enc"
TXT_FILE = "/home/user/compromised.txt"
PASSWORD = "NetSec2023"
EXPECTED_SUBJECTS = ["admin_user", "system_backdoor"]

def test_plaintext_file_removed():
    """Verify that the plaintext file was securely deleted or removed."""
    assert not os.path.exists(TXT_FILE), f"The plaintext file {TXT_FILE} still exists. It should have been removed."

def test_encrypted_file_exists():
    """Verify that the encrypted file exists."""
    assert os.path.exists(ENC_FILE), f"The encrypted file {ENC_FILE} does not exist."
    assert os.path.isfile(ENC_FILE), f"The path {ENC_FILE} is not a regular file."

def test_encrypted_file_permissions():
    """Verify that the encrypted file has exactly 600 permissions."""
    assert os.path.exists(ENC_FILE), f"Cannot check permissions: {ENC_FILE} does not exist."
    st = os.stat(ENC_FILE)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o600, f"Permissions for {ENC_FILE} are {oct(mode)}, but expected 0o600."

def test_encrypted_file_contents():
    """Verify that the encrypted file can be decrypted and contains the correct subjects."""
    assert os.path.exists(ENC_FILE), f"Cannot check contents: {ENC_FILE} does not exist."

    # Try decrypting with pbkdf2 first (modern openssl default)
    cmd_pbkdf2 = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-in", ENC_FILE,
        "-pass", f"pass:{PASSWORD}"
    ]

    # Try decrypting without pbkdf2 (older openssl default)
    cmd_no_pbkdf2 = [
        "openssl", "enc", "-d", "-aes-256-cbc",
        "-in", ENC_FILE,
        "-pass", f"pass:{PASSWORD}"
    ]

    decrypted_text = None

    try:
        result = subprocess.run(cmd_pbkdf2, capture_output=True, text=True, check=True)
        decrypted_text = result.stdout
    except subprocess.CalledProcessError:
        try:
            result = subprocess.run(cmd_no_pbkdf2, capture_output=True, text=True, check=True)
            decrypted_text = result.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to decrypt {ENC_FILE} using AES-256-CBC and the provided password. Ensure it was encrypted correctly.")

    assert decrypted_text is not None, "Decryption yielded no text."

    # Parse the decrypted text
    lines = [line.strip() for line in decrypted_text.strip().splitlines() if line.strip()]

    assert lines == EXPECTED_SUBJECTS, (
        f"The decrypted contents do not match the expected output.\n"
        f"Expected: {EXPECTED_SUBJECTS}\n"
        f"Got: {lines}\n"
        f"Ensure you extracted unique subjects, sorted them alphabetically, and selected only 'alg: none' JWTs."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
