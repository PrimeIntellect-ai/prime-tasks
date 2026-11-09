#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import hashlib
import pytest

MALICIOUS_PAYLOAD_PATH = "/home/user/malicious_payload.txt"
PAYLOAD_HASH_PATH = "/home/user/payload_hash.txt"
EXPECTED_PAYLOAD = "uploads/../../../etc/passwd"

def test_malicious_payload_exists_and_content():
    """Verify that malicious_payload.txt exists and contains the correct decoded string."""
    assert os.path.exists(MALICIOUS_PAYLOAD_PATH), f"File {MALICIOUS_PAYLOAD_PATH} does not exist."
    assert os.path.isfile(MALICIOUS_PAYLOAD_PATH), f"Path {MALICIOUS_PAYLOAD_PATH} is not a file."

    with open(MALICIOUS_PAYLOAD_PATH, 'r') as f:
        content = f.read()

    # The string might have a trailing newline depending on how it was created
    assert content.strip('\n') == EXPECTED_PAYLOAD, f"Content of {MALICIOUS_PAYLOAD_PATH} does not match the expected decoded payload."

def test_malicious_payload_permissions():
    """Verify that malicious_payload.txt has strictly 600 permissions."""
    assert os.path.exists(MALICIOUS_PAYLOAD_PATH), f"File {MALICIOUS_PAYLOAD_PATH} does not exist."

    st = os.stat(MALICIOUS_PAYLOAD_PATH)
    permissions = stat.S_IMODE(st.st_mode)

    assert permissions == 0o600, f"Permissions of {MALICIOUS_PAYLOAD_PATH} are {oct(permissions)}, expected 0o600."

def test_payload_hash_exists_and_content():
    """Verify that payload_hash.txt exists and contains the correct sha256sum output."""
    assert os.path.exists(PAYLOAD_HASH_PATH), f"File {PAYLOAD_HASH_PATH} does not exist."
    assert os.path.isfile(PAYLOAD_HASH_PATH), f"Path {PAYLOAD_HASH_PATH} is not a file."

    assert os.path.exists(MALICIOUS_PAYLOAD_PATH), f"File {MALICIOUS_PAYLOAD_PATH} must exist to verify its hash."

    # Compute the actual SHA256 hash of the malicious payload file
    sha256_hash = hashlib.sha256()
    with open(MALICIOUS_PAYLOAD_PATH, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    actual_hash = sha256_hash.hexdigest()

    with open(PAYLOAD_HASH_PATH, 'r') as f:
        hash_file_content = f.read().strip()

    # Check if the computed hash is in the file (to handle sha256sum format)
    assert actual_hash in hash_file_content, f"The expected SHA256 hash ({actual_hash}) was not found in {PAYLOAD_HASH_PATH}."
    assert MALICIOUS_PAYLOAD_PATH in hash_file_content or os.path.basename(MALICIOUS_PAYLOAD_PATH) in hash_file_content, \
        f"The filename was not found in the sha256sum output in {PAYLOAD_HASH_PATH}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
