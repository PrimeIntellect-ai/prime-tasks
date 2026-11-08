#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import re

def parse_log_files(base_dir):
    log_files = glob.glob(os.path.join(base_dir, "**", "*.log"), recursive=True)
    entries = []

    for log_file in log_files:
        with open(log_file, 'r') as f:
            current_entry = None
            for line in f:
                line = line.strip('\n')
                if line.startswith('['):
                    if current_entry:
                        entries.append(current_entry)
                    current_entry = line
                else:
                    if current_entry is not None:
                        current_entry += '\t' + line
            if current_entry:
                entries.append(current_entry)

    # Filter and format
    formatted_entries = []
    pattern = re.compile(r'^\[(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2}:\d{2})\] \[([^\]]+)\] (.*)$')

    for entry in entries:
        match = pattern.match(entry)
        if match:
            year, month, day, time, level, message = match.groups()
            if level in ['ERROR', 'CRITICAL']:
                formatted_ts = f"{year}/{month}/{day}-{time}"
                formatted_entries.append(f"{formatted_ts}\t{level}\t{message}")

    # Sort chronologically
    formatted_entries.sort()
    return formatted_entries

def test_organized_errors_exists():
    output_file = "/home/user/organized_errors.tsv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

def test_organized_errors_content():
    output_file = "/home/user/organized_errors.tsv"
    base_dir = "/home/user/project_logs"

    expected_lines = parse_log_files(base_dir)

    with open(output_file, 'r') as f:
        actual_lines = [line.strip('\n') for line in f.readlines()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
