#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_payload_exists_and_decrypts_correctly():
    payload_file = "/home/user/payload.hex"

    assert os.path.exists(payload_file), f"Payload file not found at {payload_file}"
    assert os.path.isfile(payload_file), f"{payload_file} is not a file"

    with open(payload_file, "r") as f:
        hex_payload = f.read().strip()

    assert hex_payload, "Payload file is empty"

    try:
        payload_bytes = bytes.fromhex(hex_payload)
    except ValueError:
        pytest.fail("Payload file does not contain a valid hex string")

    assert len(payload_bytes) > 1, "Payload is too short to contain a seed and data"

    seed = payload_bytes[0]
    key = seed
    plaintext = ""

    for byte in payload_bytes[1:]:
        key = (key * 13 + 11) % 256
        plaintext += chr(byte ^ key)

    expected_plaintext = "MAGIC_C2_REQ:CMD=whoami"

    assert plaintext == expected_plaintext, f"Payload decrypted to '{plaintext}', expected '{expected_plaintext}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
