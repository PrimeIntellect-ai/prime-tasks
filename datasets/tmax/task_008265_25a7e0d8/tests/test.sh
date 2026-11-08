#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_result_log_exists_and_correct():
    """Test that the result.log file is created and contains the correct validation receipt."""
    log_path = "/home/user/result.log"
    assert os.path.exists(log_path), f"Error: The file {log_path} does not exist. Did you run the emulator?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "VALID_42", f"Error: Expected 'VALID_42' in {log_path}, got '{content}'"

def test_manifest_bin_valid():
    """Test that the generated manifest.bin contains the correct byte sequence."""
    manifest_path = "/home/user/manifest.bin"
    assert os.path.exists(manifest_path), f"Error: The file {manifest_path} does not exist."

    with open(manifest_path, "rb") as f:
        data = f.read()

    assert len(data) >= 5, f"Error: {manifest_path} is too short to be a valid manifest."

    # Recompute the expected checksum: 0x01 ^ 0x02 ^ 42
    expected_csum = 0x01 ^ 0x02 ^ 42
    expected_bytes = bytes([0x01, 0x02, 42, 0x03, expected_csum])

    assert data[:5] == expected_bytes, (
        f"Error: {manifest_path} does not start with the correct sequence of bytes. "
        f"Expected {expected_bytes.hex()}, got {data[:5].hex()}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
