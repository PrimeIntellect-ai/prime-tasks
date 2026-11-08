#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import base64
import pytest

def test_key_file_correct():
    path = "/home/user/key.txt"
    assert os.path.isfile(path), f"Missing key file at {path}"

    with open(path, "r") as f:
        key_content = f.read().strip()

    assert key_content == "sec", f"The recovered key in {path} is incorrect. Expected 'sec', got '{key_content}'."

def test_forged_cookie_file_correct():
    path = "/home/user/forged_cookie.txt"
    assert os.path.isfile(path), f"Missing forged cookie file at {path}"

    with open(path, "r") as f:
        cookie_content = f.read().strip()

    # Derive the expected cookie
    pt = b'user=system_root&role=admin'
    key = b'sec'
    res = bytes([pt[i] ^ key[i % len(key)] for i in range(len(pt))])
    expected_cookie = base64.b64encode(res).decode('utf-8')

    assert cookie_content == expected_cookie, (
        f"The forged cookie in {path} is incorrect. "
        f"Expected '{expected_cookie}', got '{cookie_content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
