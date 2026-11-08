#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import base64
import json
from pathlib import Path

def encode_b64url(data: str) -> str:
    """Helper to encode a string to Base64Url without padding."""
    return base64.urlsafe_b64encode(data.encode('utf-8')).decode('utf-8').rstrip("=")

def test_admin_token_file_exists():
    """Check that the admin_token.txt file exists."""
    token_path = Path("/home/user/admin_token.txt")
    assert token_path.exists(), "The file /home/user/admin_token.txt does not exist."
    assert token_path.is_file(), "/home/user/admin_token.txt is not a regular file."

def test_admin_token_content():
    """Check that the admin_token.txt contains the correct forged JWT."""
    token_path = Path("/home/user/admin_token.txt")
    assert token_path.exists(), "Cannot check content: /home/user/admin_token.txt is missing."

    with open(token_path, "r") as f:
        actual_token = f.read().strip()

    # Recompute the expected token
    header_json = '{"alg":"none","typ":"JWT"}'
    payload_json = '{"role":"admin"}'

    expected_header = encode_b64url(header_json)
    expected_payload = encode_b64url(payload_json)

    expected_token = f"{expected_header}.{expected_payload}."

    assert actual_token == expected_token, (
        f"The forged token is incorrect.\n"
        f"Expected: {expected_token}\n"
        f"Found:    {actual_token}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
