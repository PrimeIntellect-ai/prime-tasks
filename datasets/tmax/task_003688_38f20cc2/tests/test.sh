#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_clean_data_exists_and_correct():
    clean_data_path = "/home/user/clean_data.txt"

    assert os.path.isfile(clean_data_path), f"Error: Output file {clean_data_path} not found."

    expected_content = """1|hello world|0.85
6|this is a test|0.99
8|valid text|0.0
9|another valid text|1.0
11|too much space|0.50"""

    with open(clean_data_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, "Error: Output does not match expected result."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
