#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

INVESTIGATION_DIR = "/home/user/investigation"
RECOVERED_DATA = os.path.join(INVESTIGATION_DIR, "recovered_data.txt")
KEY_LOG = os.path.join(INVESTIGATION_DIR, "key.log")
ORIGINAL_HASH = os.path.join(INVESTIGATION_DIR, "original_hash.txt")

def test_recovered_data_exists_and_matches_hash():
    assert os.path.isfile(RECOVERED_DATA), f"Expected recovered data file {RECOVERED_DATA} is missing."
    assert os.path.isfile(ORIGINAL_HASH), f"Original hash file {ORIGINAL_HASH} is missing."

    with open(ORIGINAL_HASH, 'r') as f:
        expected_hash = f.read().strip().lower()

    with open(RECOVERED_DATA, 'rb') as f:
        recovered_content = f.read()

    actual_hash = hashlib.sha256(recovered_content).hexdigest()

    assert actual_hash == expected_hash, (
        f"The SHA-256 hash of {RECOVERED_DATA} ({actual_hash}) "
        f"does not match the expected hash ({expected_hash})."
    )

def test_key_log_exists_and_correct():
    assert os.path.isfile(KEY_LOG), f"Expected key log file {KEY_LOG} is missing."

    with open(KEY_LOG, 'r') as f:
        key_content = f.read().strip()

    expected_key = "7F3A"
    assert key_content == expected_key, (
        f"The content of {KEY_LOG} ('{key_content}') does not match the expected key ('{expected_key}'). "
        "Ensure it is exactly the 2-byte key in uppercase hexadecimal format."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
