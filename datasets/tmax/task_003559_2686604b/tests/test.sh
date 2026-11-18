#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_decrypted_file_exists():
    decrypted_path = "/home/user/decrypted.txt"
    assert os.path.isfile(decrypted_path), f"Expected decrypted file at {decrypted_path} is missing."

def test_decrypted_file_content():
    decrypted_path = "/home/user/decrypted.txt"
    assert os.path.isfile(decrypted_path), f"Expected decrypted file at {decrypted_path} is missing."

    with open(decrypted_path, "rb") as f:
        content = f.read()

    expected_content = b"The secret flag is: FLAG{tr4c1ng_4nd_d3bugg1ng_rust_c0d3}"
    assert content == expected_content, f"The content of {decrypted_path} is incorrect. Expected {expected_content}, but got {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
