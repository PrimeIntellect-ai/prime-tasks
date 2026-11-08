#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_recovered_key_file_exists():
    key_file = "/home/user/recovered_key.txt"
    assert os.path.isfile(key_file), f"The file {key_file} does not exist. Did you save the recovered key?"

def test_recovered_key_content():
    key_file = "/home/user/recovered_key.txt"
    assert os.path.isfile(key_file), f"The file {key_file} does not exist."

    with open(key_file, "r") as f:
        content = f.read().strip()

    expected_key = "FLAG{3lf_53ct10n_f0r3n51c5_8821}"
    assert content == expected_key, f"The content of {key_file} is incorrect. Expected '{expected_key}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
