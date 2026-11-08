#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

INCIDENT_DIR = "/home/user/incident"
RECOVERED_FILE = os.path.join(INCIDENT_DIR, "exfil_recovered.txt")
REDACTED_FILE = os.path.join(INCIDENT_DIR, "exfil_redacted.txt")
CHECKSUM_FILE = os.path.join(INCIDENT_DIR, "checksum.sha256")

def test_recovered_file_exists_and_matches_checksum():
    assert os.path.isfile(RECOVERED_FILE), f"Recovered file {RECOVERED_FILE} does not exist. Did you save the decrypted file?"
    assert os.path.isfile(CHECKSUM_FILE), f"Checksum file {CHECKSUM_FILE} is missing."

    with open(CHECKSUM_FILE, "r") as f:
        checksum_content = f.read().strip()

    expected_hash = checksum_content.split()[0]

    sha256_hash = hashlib.sha256()
    with open(RECOVERED_FILE, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)

    actual_hash = sha256_hash.hexdigest()

    assert actual_hash == expected_hash, f"SHA256 hash of {RECOVERED_FILE} ({actual_hash}) does not match the expected hash ({expected_hash}). The decryption might be incorrect."

def test_redacted_file_content():
    assert os.path.isfile(REDACTED_FILE), f"Redacted file {REDACTED_FILE} does not exist. Did you create the redacted version?"

    expected_content = (
        "CUSTOMER_DATA_START\n"
        "ID: 101, Name: Alice, Card: XXXX-XXXX-XXXX-4444, Balance: $500\n"
        "ID: 102, Name: Bob, Card: XXXX-XXXX-XXXX-8888, Balance: $1200\n"
        "ID: 103, Name: Charlie, Card: XXXX-XXXX-XXXX-9999, Balance: $30\n"
        "CUSTOMER_DATA_END\n"
    )

    with open(REDACTED_FILE, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The content of the redacted file does not match the expected output. Check your redaction logic for credit card numbers."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
