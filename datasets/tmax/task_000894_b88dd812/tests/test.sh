#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import pytest

PAYLOAD_PATH = '/home/user/payload.txt'


def test_payload_file_exists():
    """Test that the payload.txt file exists."""
    assert os.path.exists(PAYLOAD_PATH), f"The file {PAYLOAD_PATH} does not exist. You must write your payload here."
    assert os.path.isfile(PAYLOAD_PATH), f"The path {PAYLOAD_PATH} is not a file."


def test_payload_no_e():
    """Test that the payload does not contain the characters 'e' or 'E'."""
    with open(PAYLOAD_PATH, 'r') as f:
        payload = f.read().strip()

    assert payload, "The payload file is empty."
    assert 'e' not in payload, "The payload contains the forbidden lowercase letter 'e'."
    assert 'E' not in payload, "The payload contains the forbidden uppercase letter 'E'."


def trusted_decrypt_url(obfuscated_str):
    """Independent implementation of the supplied server-side algorithm."""
    decoded = base64.b64decode(obfuscated_str)
    reversed_bytes = decoded[::-1]
    key = b'WAFBypassToken2024'
    decrypted = bytearray()
    for i, b in enumerate(reversed_bytes):
        decrypted.append(b ^ key[i % len(key)])
    return decrypted.decode('utf-8')


def test_payload_deobfuscates_correctly():
    """Test that the payload deobfuscates to the correct URL."""
    with open(PAYLOAD_PATH, 'r') as f:
        payload = f.read().strip()

    try:
        decrypted_url = trusted_decrypt_url(payload)
    except Exception as e:
        pytest.fail(f"Failed to deobfuscate the payload. Error: {e}")

    expected_prefix = "http://redteam.htb/capture"
    assert decrypted_url.startswith(expected_prefix), (
        f"The deobfuscated URL does not start with the required prefix.\n"
        f"Expected prefix: {expected_prefix}\n"
        f"Actual URL: {decrypted_url}"
    )
TEST_EOF

if python3 -I -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
