#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

OUTPUT_FILE = "/home/user/anonymized_ips.json"
EXPECTED_IPS = {"10.5.5.1", "172.16.0.5", "8.8.8.8", "9.9.9.9"}

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."

def test_output_file_content():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_FILE} does not contain valid JSON.")

    assert isinstance(data, list), f"The JSON in {OUTPUT_FILE} must be an array (list)."
    assert all(isinstance(item, str) for item in data), "All items in the JSON array must be strings."

    expected_hashes = sorted([hashlib.sha256(ip.encode()).hexdigest() for ip in EXPECTED_IPS])

    assert data == sorted(data), "The list of hashes in the JSON file is not sorted alphabetically."
    assert len(data) == len(expected_hashes), f"Expected {len(expected_hashes)} hashes, but found {len(data)}."
    assert data == expected_hashes, f"The hashes in {OUTPUT_FILE} do not match the expected anonymized IPs."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
