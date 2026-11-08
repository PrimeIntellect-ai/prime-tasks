#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

def test_clean_data_csv():
    file_path = "/home/user/clean_data.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_content = """id,cpu_usage,memory_usage,status_msg
1,45.5,60.2,System running smoothly
2,95.0,88.1,Warning High Load!
5,20.0,30.0,All OK
8,80.5,75.0,Load increasing
10,60.0,65.0,Check fan speed"""

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {file_path} does not match expected."

def test_tokens_txt():
    file_path = "/home/user/tokens.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_tokens = [
        "all", "check", "fan", "high", "increasing", "load", "ok", 
        "running", "smoothly", "speed", "system", "warning"
    ]

    with open(file_path, "r") as f:
        actual_tokens = [line.strip() for line in f if line.strip()]

    assert actual_tokens == expected_tokens, f"Content of {file_path} does not match expected tokens."

def test_correlation_txt():
    file_path = "/home/user/correlation.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    # The correlation should be exactly 0.9767
    assert actual_content == "0.9767", f"Content of {file_path} does not match expected correlation (0.9767). Found: {actual_content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
