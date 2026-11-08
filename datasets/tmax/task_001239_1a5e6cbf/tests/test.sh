#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import difflib
import subprocess
import pytest

def test_clean_log_similarity():
    target_file = '/home/user/clean.log'
    expected_file = '/tests/expected_clean.log'

    assert os.path.isfile(target_file), f"Target log file {target_file} is missing."
    assert os.path.isfile(expected_file), f"Expected log file {expected_file} is missing."

    with open(target_file, 'r') as f:
        target_text = f.read()
    with open(expected_file, 'r') as f:
        expected_text = f.read()

    ratio = difflib.SequenceMatcher(None, target_text.strip(), expected_text.strip()).ratio()

    assert ratio >= 0.98, f"Similarity score {ratio:.4f} is below the threshold of 0.98"

def test_new_key_generated():
    key_path = "/home/user/new_key.pem"
    assert os.path.isfile(key_path), f"New key file {key_path} is missing."

    # Verify it is a valid RSA key and has no passphrase
    result = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-check", "-noout"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Failed to read the new key. It might be encrypted with a passphrase or invalid. Error: {result.stderr}"
    assert "RSA key ok" in result.stdout, "The generated key is not a valid RSA key."

    # Verify it is 2048-bit
    result_text = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-text", "-noout"],
        capture_output=True,
        text=True
    )
    assert "Private-Key: (2048 bit" in result_text.stdout, "The generated RSA key is not 2048-bit."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
