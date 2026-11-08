#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_cwe_file():
    cwe_path = "/home/user/cwe.txt"
    assert os.path.isfile(cwe_path), f"The file {cwe_path} does not exist."

    with open(cwe_path, 'r') as f:
        content = f.read().strip()

    assert content.upper() == "CWE-327", f"Expected CWE-327 in {cwe_path}, but found '{content}'."

def test_forged_token_file():
    token_path = "/home/user/forged_token.txt"
    assert os.path.isfile(token_path), f"The file {token_path} does not exist."

    with open(token_path, 'r') as f:
        hex_content = f.read().strip()

    assert hex_content, f"The file {token_path} is empty."

    try:
        decoded_bytes = bytes.fromhex(hex_content)
    except ValueError:
        assert False, f"The content of {token_path} is not a valid hexadecimal string."

    key = 0x5A
    decrypted_chars = [chr(b ^ key) for b in decoded_bytes]
    decrypted_string = "".join(decrypted_chars)

    assert "role=admin" in decrypted_string, (
        f"The decrypted token does not contain 'role=admin'. "
        f"Decrypted string was: {repr(decrypted_string)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
