#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hashlib
import pytest

def test_rotated_cookie_exists():
    rotated_file = '/home/user/rotated_cookie.log'
    assert os.path.exists(rotated_file), f"The file {rotated_file} does not exist."
    assert os.path.isfile(rotated_file), f"{rotated_file} is not a regular file."

def test_rotated_cookie_content():
    rotated_file = '/home/user/rotated_cookie.log'
    assert os.path.exists(rotated_file), f"Cannot check content, {rotated_file} missing."

    with open(rotated_file, 'r') as f:
        content = f.read()

    assert not content.endswith('\n'), "The file must not contain trailing newlines."

    prefix = "Cookie: auth_session="
    assert content.startswith(prefix), f"The file content must start with '{prefix}'."

    b64_str = content[len(prefix):]

    try:
        json_bytes = base64.b64decode(b64_str, validate=True)
    except Exception as e:
        pytest.fail(f"Failed to base64-decode the cookie value: {e}")

    try:
        json_str = json_bytes.decode('utf-8')
    except UnicodeDecodeError:
        pytest.fail("The decoded base64 value is not valid UTF-8.")

    try:
        data = json.loads(json_str)
    except json.JSONDecodeError as e:
        pytest.fail(f"The decoded cookie is not valid JSON: {e}")

    # Verify the contents of the JSON
    assert data.get('user') == 'admin', "The 'user' field should be 'admin'."
    assert data.get('role') == 'admin', "The 'role' field should be 'admin'."
    assert data.get('profile_pic') == 'default.png', "The 'profile_pic' field was not properly sanitized to 'default.png'."

    expected_hash = hashlib.sha256(b"NewSecurePassword123!").hexdigest()
    assert data.get('token_hash') == expected_hash, "The 'token_hash' does not match the SHA-256 hash of the new password."

    # Verify compact serialization of the submitted object.
    submitted_compact_json = json.dumps(data, separators=(',', ':'))
    submitted_compact_b64 = base64.b64encode(submitted_compact_json.encode('utf-8')).decode('utf-8')
    assert b64_str == submitted_compact_b64, "The base64 encoded string does not match the expected compact JSON serialization (no spaces between keys and values)."

    # Verify that the original object was preserved exactly, including key order,
    # with only profile_pic and token_hash changed.
    expected_data = {
        'user': 'admin',
        'token_hash': expected_hash,
        'profile_pic': 'default.png',
        'role': 'admin',
    }
    assert data == expected_data, "The session object contains missing, changed, or extra fields."
    assert list(data.keys()) == list(expected_data.keys()), "The session object's key order does not match the original object."

    expected_json_str = json.dumps(expected_data, separators=(',', ':'))
    expected_b64 = base64.b64encode(expected_json_str.encode('utf-8')).decode('utf-8')
    assert json_str == expected_json_str, "The decoded JSON is not the exact expected updated session serialization."
    assert b64_str == expected_b64, "The base64 encoded string does not match the exact expected updated session object."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
