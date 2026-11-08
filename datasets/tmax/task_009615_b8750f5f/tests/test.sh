#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cracked_password_file():
    """Verify that cracked_password.txt exists and contains the correct password."""
    filepath = "/home/user/cracked_password.txt"
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content == "shadowoperat0r", f"Incorrect password in {filepath}. Found: {content}"

def test_payload_elf_file():
    """Verify that payload.elf exists and is a valid ELF binary."""
    filepath = "/home/user/payload.elf"
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "rb") as f:
        magic = f.read(4)

    assert magic == b"\x7fELF", f"File {filepath} does not have a valid ELF header."

def test_c2_address_file():
    """Verify that c2_address.txt exists and contains the correct C2 address."""
    filepath = "/home/user/c2_address.txt"
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content == "https://10.10.99.55:4444/callback", f"Incorrect C2 address in {filepath}. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
