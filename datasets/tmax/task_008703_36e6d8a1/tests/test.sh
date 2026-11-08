#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_recovered_params():
    path = "/home/user/legacy_project/recovered_params.txt"
    assert os.path.isfile(path), f"File {path} does not exist. You must recover the deleted file and save it here."
    with open(path, "r") as f:
        content = f.read()
    assert "PARAM_A=42.5" in content, "PARAM_A=42.5 not found in recovered_params.txt. The file might not be correctly recovered."
    assert "PARAM_B=99.1" in content, "PARAM_B=99.1 not found in recovered_params.txt. The file might not be correctly recovered."

def test_buggy_line_number():
    path = "/home/user/legacy_project/buggy_line_number.txt"
    assert os.path.isfile(path), f"File {path} does not exist. You must write the buggy line number to this file."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "8", f"Expected buggy line number to be 8, but got '{content}'."

def test_secret_threshold():
    path = "/home/user/legacy_project/secret_threshold.txt"
    assert os.path.isfile(path), f"File {path} does not exist. You must write the secret threshold value to this file."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "867.5309", f"Expected secret threshold to be 867.5309, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
