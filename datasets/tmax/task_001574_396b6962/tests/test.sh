#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_new_key_txt():
    path = "/home/user/new_key.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "rb") as f:
        content = f.read()

    expected_key = b"n3w_s3cur3_k3y_2024"
    assert content == expected_key, f"File {path} content does not exactly match the expected key. Got: {content!r}"

def test_integrity_check_txt():
    path = "/home/user/integrity_check.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == "VERIFIED", f"File {path} content is incorrect. Expected 'VERIFIED', got '{content}'."

def test_cwe_vulnerability_txt():
    path = "/home/user/cwe_vulnerability.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    valid_cwes = {"CWE-328", "CWE-327"}
    assert content in valid_cwes, f"File {path} content is incorrect. Expected one of {valid_cwes}, got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
