#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import re

def test_flag_file():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"Flag file {flag_path} does not exist."
    with open(flag_path, "r") as f:
        content = f.read().strip()
    assert content == "FLAG{c_evasi0n_m4st3r}", f"Flag file content is incorrect. Got: {content}"

def test_payload_binary_and_hash():
    payload_path = "/home/user/payload"
    log_path = "/home/user/server.log"

    assert os.path.isfile(payload_path), f"Payload binary {payload_path} does not exist."
    assert os.path.isfile(log_path), f"Server log {log_path} does not exist."

    # Compute true SHA-256 of the payload binary
    sha256_hash = hashlib.sha256()
    with open(payload_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    true_hash = sha256_hash.hexdigest()

    # Read the server log to find the logged hash
    with open(log_path, "r") as f:
        log_content = f.read()

    # Extract the last logged hash (in case of multiple attempts)
    hashes = re.findall(r"HASH:\s*([a-f0-9]{64})", log_content, re.IGNORECASE)
    assert hashes, "No valid SHA-256 hash found in server log."

    logged_hash = hashes[-1].lower()
    assert logged_hash == true_hash, f"The logged hash ({logged_hash}) does not match the actual payload hash ({true_hash})."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
