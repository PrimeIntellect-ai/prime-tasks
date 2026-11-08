#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def generate_token(pin: int, user: str) -> int:
    """Re-implementation of the C token generation logic."""
    hash_val = pin
    for char in user:
        # Simulate 32-bit unsigned integer overflow
        hash_val = ((hash_val * 33) & 0xFFFFFFFF) ^ ord(char)
    return hash_val

def test_cracked_pin():
    """Verify that the cracked PIN is correctly written to cracked_pin.txt."""
    pin_file = "/home/user/pentest/cracked_pin.txt"
    assert os.path.isfile(pin_file), f"Expected file {pin_file} does not exist."

    with open(pin_file, 'r') as f:
        content = f.read().strip()

    assert content == "4281", f"The cracked PIN in {pin_file} is incorrect. Found: '{content}'"

def test_root_token():
    """Verify that the new root token is correctly generated and written to root_token.txt."""
    token_file = "/home/user/pentest/root_token.txt"
    assert os.path.isfile(token_file), f"Expected file {token_file} does not exist."

    with open(token_file, 'r') as f:
        content = f.read().strip().lower()

    expected_token = f"0x{generate_token(4281, 'root'):08x}"

    assert content == expected_token, f"The root token in {token_file} is incorrect. Expected: '{expected_token}', Found: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
