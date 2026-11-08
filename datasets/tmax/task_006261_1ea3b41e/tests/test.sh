#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_flag_file_exists_and_correct():
    """Test that the flag file exists and contains the correct flag."""
    flag_path = "/home/user/flag.txt"
    expected_flag = "FLAG{jwt_n0n3_alg_byp4ss_5ucc3ss}"

    # Check if file exists
    assert os.path.isfile(flag_path), f"The flag file was not found at {flag_path}. Did you save the output to the correct location?"

    # Check the content of the file
    with open(flag_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == expected_flag, f"The content of {flag_path} is incorrect. Expected '{expected_flag}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
