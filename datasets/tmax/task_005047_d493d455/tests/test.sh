#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_passphrase_recovered():
    """Verify that the passphrase was successfully recovered and saved."""
    file_path = "/home/user/investigation/passphrase.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you save the recovered passphrase?"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_passphrase = "purplemonkey123"
    assert content == expected_passphrase, f"The contents of {file_path} do not match the expected passphrase."

def test_secret_decrypted():
    """Verify that the secret message was decrypted correctly."""
    file_path = "/home/user/investigation/secret.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you decrypt the secret message?"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_secret = "The payload was deployed via the vulnerable logging endpoint."
    assert content == expected_secret, f"The contents of {file_path} do not match the expected decrypted message."

def test_logs_redacted():
    """Verify that the credit card numbers in the logs were correctly redacted."""
    file_path = "/home/user/investigation/clean_logs.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you save the redacted logs?"

    with open(file_path, "r") as f:
        content = f.read()

    expected_logs = (
        "[2023-10-01 10:12:45] INFO: User login successful.\n"
        "[2023-10-01 10:13:01] ERROR: Failed payment transaction for CC [REDACTED]. Error code 500.\n"
        "[2023-10-01 10:15:22] DEBUG: Raw payload: {\"card\": \"[REDACTED]\", \"cvv\": \"123\"}\n"
        "[2023-10-01 10:18:00] INFO: Processed 1234 items. No issues found.\n"
        "[2023-10-01 10:20:11] WARN: Retry for account [REDACTED] triggered.\n"
    )

    # Normalize line endings and trailing whitespace for robust comparison
    clean_content = "\n".join(line.strip() for line in content.strip().splitlines())
    clean_expected = "\n".join(line.strip() for line in expected_logs.strip().splitlines())

    assert clean_content == clean_expected, "The redacted logs do not match the expected output. Ensure only the 16-digit credit card numbers (with or without hyphens) are replaced with '[REDACTED]'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
