#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def compute_expected_output(input_path):
    expected_lines = []
    user_last_rt = {}
    user_history = {}

    hex_escape_re = re.compile(r'\\x[0-9a-fA-F]{2}')

    with open(input_path, 'r', encoding='utf-8') as f:
        for line in f:
            # Clean invalid hex escapes
            cleaned_line = hex_escape_re.sub('', line)

            try:
                data = json.loads(cleaned_line)
            except json.JSONDecodeError:
                continue

            ts = data.get("timestamp")
            user = data.get("user_id")
            rt = data.get("response_time_ms")

            # Imputation
            if rt is None:
                rt = user_last_rt.get(user, 0)

            user_last_rt[user] = rt

            # Rolling average
            if user not in user_history:
                user_history[user] = []
            user_history[user].append(rt)

            # Keep only last 3
            if len(user_history[user]) > 3:
                user_history[user] = user_history[user][-3:]

            avg = sum(user_history[user]) / len(user_history[user])

            expected_lines.append(f"{ts},{user},{rt},{avg:.2f}")

    return expected_lines

def test_analyzed_logs_exists():
    """Verify that the analyzed_logs.csv file was created."""
    file_path = "/home/user/analyzed_logs.csv"
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} exists but is not a file."

def test_analyzed_logs_content():
    """Verify that the analyzed_logs.csv file has the correct content based on the input."""
    input_path = "/home/user/server_logs.jsonl"
    output_path = "/home/user/analyzed_logs.csv"

    assert os.path.exists(input_path), f"The input file {input_path} is missing. Cannot verify."

    expected_lines = compute_expected_output(input_path)

    with open(output_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
