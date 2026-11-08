#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib

def test_decrypted_log_exists_and_correct():
    log_path = "/home/user/investigation/decrypted.log"
    assert os.path.isfile(log_path), f"The output file {log_path} was not found. Did the Rust program run successfully?"

    with open(log_path, "rb") as f:
        data = f.read()

    actual_hash = hashlib.sha256(data).hexdigest()
    expected_hash = "5e07672dc634ab9a1f29013c7717fcba28af4b5b7bdfd9422df5003b8e75db34"

    assert actual_hash == expected_hash, (
        f"The content of {log_path} is incorrect. "
        f"Expected SHA-256 hash: {expected_hash}, but got: {actual_hash}. "
        "Make sure the decoding logic correctly handles the URL-safe base64 payload."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
