#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_clean_features_csv_exists_and_content():
    output_path = "/home/user/clean_features.csv"

    # Check if file exists
    assert os.path.exists(output_path), f"Error: Output file {output_path} not found."
    assert os.path.isfile(output_path), f"Error: {output_path} is not a regular file."

    expected_lines = [
        "user_id,email_lower,email_domain,age,joined_year",
        "101,alice@example.com,example.com,25,2023",
        "102,bob@gmail.com,gmail.com,30,2022",
        "105,eve@hacker.net,hacker.net,45,2019",
        "108,heidi@university.edu,university.edu,19,2023"
    ]

    with open(output_path, 'r') as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.split('\n') if line.strip()]

    assert len(actual_lines) > 0, f"Error: {output_path} is empty."

    # Check the header
    assert actual_lines[0] == expected_lines[0], f"Error: Header row is incorrect. Expected '{expected_lines[0]}', got '{actual_lines[0]}'."

    # Check the data records (order matters as it must be sorted by user_id)
    assert actual_lines == expected_lines, (
        "Error: The content of the output CSV does not match the expected result.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
