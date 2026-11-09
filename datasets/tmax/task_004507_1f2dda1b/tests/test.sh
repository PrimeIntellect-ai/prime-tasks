#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import pytest

REPORT_PATH = "/home/user/investigation_report.txt"
UPLOADS_DIR = "/home/user/uploads"

def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."

def test_report_content():
    # Find the ELF file dynamically to be robust
    elf_file = None
    for filename in os.listdir(UPLOADS_DIR):
        filepath = os.path.join(UPLOADS_DIR, filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    elf_file = filename
                    break

    assert elf_file is not None, "Could not find any ELF file in the uploads directory."

    # Extract the token dynamically
    filepath = os.path.join(UPLOADS_DIR, elf_file)
    with open(filepath, "rb") as f:
        content = f.read()

    token_prefix = b"AUTH_TOKEN="
    start_idx = content.find(token_prefix)
    assert start_idx != -1, f"Could not find {token_prefix.decode()} in the ELF file."

    end_idx = content.find(b"\0", start_idx)
    if end_idx == -1:
        end_idx = len(content)

    full_token = content[start_idx:end_idx].decode('utf-8', errors='ignore')
    token_value = full_token[len("AUTH_TOKEN="):]

    expected_hash = hashlib.sha256(token_value.encode('utf-8')).hexdigest()

    expected_report = (
        f"Suspicious File: {elf_file}\n"
        f"Token: {full_token}\n"
        f"Hash: {expected_hash}\n"
    )

    with open(REPORT_PATH, "r") as f:
        actual_report = f.read()

    assert actual_report.strip() == expected_report.strip(), (
        f"The content of {REPORT_PATH} does not match the expected format or values.\n"
        f"Expected:\n{expected_report.strip()}\n"
        f"Actual:\n{actual_report.strip()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
