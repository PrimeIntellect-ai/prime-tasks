#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_accepted_logs_exists_and_content():
    expected_file = "/home/user/accepted_logs.txt"

    assert os.path.exists(expected_file), f"Output file {expected_file} is missing. Did the C++ program run and generate it?"
    assert os.path.isfile(expected_file), f"Path {expected_file} is not a file."

    expected_lines = [
        "Hello",
        "World",
        "Invalid@base64",
        "NextSec",
        "Skipped",
        "Another"
    ]

    with open(expected_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {expected_file} do not match the expected output. "
        f"Expected: {expected_lines}, but got: {actual_lines}"
    )

def test_source_code_exists():
    source_file = "/home/user/process_requests.cpp"
    assert os.path.exists(source_file), f"Source file {source_file} is missing."
    assert os.path.isfile(source_file), f"Path {source_file} is not a file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
