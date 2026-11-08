#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import binascii
import urllib.request
import urllib.error
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend

EXPECTED_FLAG = "FLAG{cbc_b1t_fl1pp1ng_m4st3r}"
EXPECTED_PLAINTEXT = b"<svg onload=1>"
KEY_PATH = "/root/cbc_service.key"
SUCCESS_PATH = "/tmp/success.log"


def test_flag_file_exists_and_correct():
    """Verify that the flag file exists and contains the correct flag."""
    flag_path = '/home/user/flag.txt'
    assert os.path.isfile(flag_path), f"Flag file not found at {flag_path}"

    with open(flag_path, 'r') as f:
        content = f.read().strip()

    assert content == EXPECTED_FLAG, f"Flag file content is incorrect. Expected '{EXPECTED_FLAG}', got '{content}'"


def test_payload_file_and_validity():
    """Independently decrypt the token, then verify it against the protected service."""
    payload_path = '/home/user/payload.txt'
    assert os.path.isfile(payload_path), f"Payload file not found at {payload_path}"

    with open(payload_path, 'r') as f:
        token = f.read().strip()

    assert token.count(':') == 1, "Payload token must be in the format 'hex_iv:hex_ciphertext'"
    hex_iv, hex_ct = token.split(':')
    try:
        iv = binascii.unhexlify(hex_iv)
        ciphertext = binascii.unhexlify(hex_ct)
    except (binascii.Error, ValueError) as exc:
        assert False, f"Payload contains invalid hexadecimal data: {exc}"

    assert len(iv) == 16, "Payload IV must be exactly 16 bytes"
    assert ciphertext and len(ciphertext) % 16 == 0, "Ciphertext must contain complete AES blocks"

    assert os.path.isfile(KEY_PATH), "Protected service key is unavailable"
    with open(KEY_PATH, 'rb') as f:
        key = f.read()
    assert len(key) == 16, "Protected service key is invalid"

    try:
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()
        padded = decryptor.update(ciphertext) + decryptor.finalize()
        unpadder = padding.PKCS7(128).unpadder()
        plaintext = unpadder.update(padded) + unpadder.finalize()
    except Exception as exc:
        assert False, f"Payload does not decrypt with valid PKCS#7 padding: {exc}"

    assert plaintext == EXPECTED_PLAINTEXT, f"Payload decrypts to {plaintext!r}, not the required exact payload"

    # This root-owned log can only have received the flag from the protected service.
    assert os.path.isfile(SUCCESS_PATH), "The token was not submitted successfully before verification"
    with open(SUCCESS_PATH, 'r') as f:
        assert f.read().strip() == EXPECTED_FLAG, "The protected service did not record a successful submission"

    # Keep the original live service assertions as well.
    url = 'http://127.0.0.1:8080/submit'
    data = json.dumps({"token": token}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            resp_data = json.loads(response.read().decode('utf-8'))
            assert resp_data.get('status') == 'success', f"Server rejected the payload token. Response: {resp_data}"
            assert resp_data.get('message') == 'Evasion successful!', "Payload did not trigger the expected success message."
    except urllib.error.URLError as e:
        if hasattr(e, 'read'):
            error_body = e.read().decode('utf-8')
            assert False, f"Failed to submit payload to server. HTTP Error {e.code}: {error_body}"
        assert False, f"Failed to connect to server at {url}: {e.reason}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
