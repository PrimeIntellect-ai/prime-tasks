#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_solution_file_exists_and_correct():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"The solution file {solution_path} is missing."

    with open(solution_path, "r") as f:
        content = f.read().strip()

    expected_flag = "FLAG{d3bugfs_str4c3_m4st3r}"
    assert expected_flag in content, f"The solution file does not contain the correct flag. Found: {content}"

def test_recovered_payload_exists():
    recovered_path = "/home/user/recovered.bin"
    assert os.path.isfile(recovered_path), f"The recovered payload {recovered_path} is missing."
    assert os.path.getsize(recovered_path) > 0, f"The recovered payload {recovered_path} is empty."

def test_key_file_exists():
    key_path = "/home/user/.local/share/key.txt"
    assert os.path.isfile(key_path), f"The key file {key_path} was not created."
    with open(key_path, "r") as f:
        content = f.read().strip()
    assert content.startswith("S3cr3t"), f"The key file {key_path} does not contain the correct key."

def test_flag_decoded_exists():
    flag_path = "/home/user/flag_decoded.txt"
    assert os.path.isfile(flag_path), f"The decoded flag file {flag_path} is missing. Did you run the decryptor?"
    with open(flag_path, "r") as f:
        content = f.read().strip()
    expected_flag = "FLAG{d3bugfs_str4c3_m4st3r}"
    assert expected_flag in content, f"The decoded flag file does not contain the expected flag."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
