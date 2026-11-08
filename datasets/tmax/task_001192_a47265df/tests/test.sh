#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pickle
import pytest

def is_prime(n):
    if n < 2:
        return False
    for i in range(2, int(n**0.5) + 1):
        if n % i == 0:
            return False
    return True

def test_verification_json_exists():
    """Test that the verification.json file was created."""
    file_path = "/home/user/migration/verification.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The script did not create the output file."

def test_verification_json_content():
    """Test that the verification.json file contains the correct results."""
    file_path = "/home/user/migration/verification.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "is_valid_constraint" in result, "Key 'is_valid_constraint' is missing in the JSON output."
    assert "legacy_checksum" in result, "Key 'legacy_checksum' is missing in the JSON output."

    # Recompute expected values based on the payload
    payload_path = "/home/user/migration/payload.pkl"
    assert os.path.isfile(payload_path), f"Payload file {payload_path} is missing."

    with open(payload_path, 'rb') as f:
        data = pickle.load(f)

    expected_is_valid = sum(data) == 277 and all(is_prime(x) for x in data)

    data_str = ",".join(str(x) for x in data)
    checksum = 0
    for i, byte_val in enumerate(data_str.encode('ascii')):
        checksum += byte_val * (i + 1)
    expected_checksum = checksum % 1024

    assert result["is_valid_constraint"] == expected_is_valid, f"Expected is_valid_constraint to be {expected_is_valid}, got {result['is_valid_constraint']}"
    assert result["legacy_checksum"] == expected_checksum, f"Expected legacy_checksum to be {expected_checksum}, got {result['legacy_checksum']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
