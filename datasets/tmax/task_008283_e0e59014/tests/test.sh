#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_flag_file_exists_and_correct():
    flag_file = "/home/user/flag.txt"

    # Check that the flag file exists
    assert os.path.exists(flag_file), f"Missing required file: {flag_file}"
    assert os.path.isfile(flag_file), f"Path is not a file: {flag_file}"

    # Read the contents of the flag file
    with open(flag_file, "r", encoding="utf-8") as f:
        content = f.read()

    expected_flag = "zK9#mP2@qL5_vX"

    assert content == expected_flag, f"Flag file content is incorrect. Expected '{expected_flag}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
