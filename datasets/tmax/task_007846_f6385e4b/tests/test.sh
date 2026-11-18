#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib

def test_final_restored_file():
    final_path = "/home/user/final_restored.txt"

    assert os.path.exists(final_path), f"The file {final_path} does not exist. Did you save the final output to the correct path?"
    assert os.path.isfile(final_path), f"The path {final_path} is not a file."

    with open(final_path, "rb") as f:
        actual_content = f.read()

    expected_content = b"A" * 150 + b"B" * 100 + b"D" * 50 + b"\nBase data line 1 modified.\nLine 2.\nLine 3 added.\n"

    actual_hash = hashlib.sha256(actual_content).hexdigest()
    expected_hash = hashlib.sha256(expected_content).hexdigest()

    assert actual_hash == expected_hash, (
        f"The content of {final_path} is incorrect.\n"
        f"Expected SHA-256: {expected_hash}\n"
        f"Actual SHA-256: {actual_hash}\n"
        "Ensure you correctly combined the split tarball, decoded the RLE file, and applied the patch."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
