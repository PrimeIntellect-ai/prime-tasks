#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_parser_cpp_exists():
    assert os.path.isfile('/home/user/parser.cpp'), "The C++ program /home/user/parser.cpp was not found."

def test_db_import_csv():
    output_file = '/home/user/db_import.csv'
    assert os.path.isfile(output_file), f"The output file {output_file} was not found."

    logs_dir = '/home/user/logs'
    log_files = [os.path.join(logs_dir, f) for f in os.listdir(logs_dir) if f.endswith('.log')]

    expected_lines = []
    pattern = re.compile(r"\[(.*?)\] \[(.*?)\] CONFIG_UPDATE: (.*?) changed from '(.*?)' to '(.*?)'")

    for log_file in log_files:
        with open(log_file, 'r') as f:
            for line in f:
                match = pattern.search(line)
                if match:
                    timestamp, service, key, old_val, new_val = match.groups()
                    expected_lines.append(f"{timestamp},{service},{key},{old_val},{new_val}\n")

    expected_lines.sort()

    with open(output_file, 'r') as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_file}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual.strip() == expected.strip(), f"Line {i+1} mismatch.\nExpected: {expected.strip()}\nActual: {actual.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
