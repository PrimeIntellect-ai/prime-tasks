#!/bin/bash
set -e
mkdir -p /logs/verifier

TEST_DIR=$(mktemp -d /tmp/vault-verifier.XXXXXX)
chmod 700 "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

cat << 'TEST_EOF' > "$TEST_DIR/test_final_state.py"
import os
import json
import binascii
import hashlib
import pytest
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

IV = b'0123456789abcdef'


def test_admin_token_valid():
    """Test that the admin token is correctly generated and saved."""
    token_path = '/home/user/admin_token.txt'
    assert os.path.exists(token_path), f"File {token_path} does not exist. Did you save the admin token?"

    with open(token_path, 'r') as f:
        hex_data = f.read().strip()

    assert hex_data, f"File {token_path} is empty."

    try:
        ciphertext = binascii.unhexlify(hex_data)
    except (binascii.Error, ValueError) as e:
        pytest.fail(f"Contents of {token_path} are not valid hex: {e}")

    # Validate independently instead of importing the agent-writable service.py.
    expected_pin = '7391'
    key = hashlib.md5(expected_pin.zfill(4).encode()).digest()

    try:
        cipher = AES.new(key, AES.MODE_CBC, iv=IV)
        decrypted = unpad(cipher.decrypt(ciphertext), AES.block_size)
        payload = json.loads(decrypted.decode())
    except Exception as e:
        pytest.fail(f"Failed to decrypt the token using the correct PIN. Is it encrypted properly? Error: {e}")

    assert isinstance(payload, dict), f"Decrypted payload is not a JSON object, got: {type(payload)}"
    assert payload.get('user') == 'admin', f"Expected user 'admin', but got '{payload.get('user')}'"
    assert payload.get('role') == 'root', f"Expected role 'root', but got '{payload.get('role')}'"
    assert payload == {'user': 'admin', 'role': 'root'}, f"Decrypted payload contains unexpected data: {payload}"
TEST_EOF

unset PYTHONPATH PYTHONHOME
export PYTHONNOUSERSITE=1
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1

if (cd / && python3 -m pytest "$TEST_DIR/test_final_state.py" -x --tb=short) 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
