#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cleaned_logs_exists():
    """Verify that the cleaned_logs.txt file exists."""
    cleaned_logs_path = "/home/user/cleaned_logs.txt"
    assert os.path.exists(cleaned_logs_path), f"The final output file {cleaned_logs_path} is missing."
    assert os.path.isfile(cleaned_logs_path), f"The path {cleaned_logs_path} exists but is not a file."

def test_cleaned_logs_content():
    """Verify that cleaned_logs.txt contains the correct sorted, non-debug lines."""
    cleaned_logs_path = "/home/user/cleaned_logs.txt"

    expected_lines = [
        "2023-10-01 10:00:01 [INFO] System startup initiated\n",
        "2023-10-01 10:00:03 [ERROR] Failed to load module X\n",
        "2023-10-01 10:02:00 [WARN] High memory usage detected\n",
        "2023-10-01 10:02:10 [INFO] System stable\n"
    ]

    with open(cleaned_logs_path, 'r') as f:
        actual_lines = f.readlines()

    # Strip trailing newlines for a cleaner comparison and error message
    actual_stripped = [line.strip() for line in actual_lines if line.strip()]
    expected_stripped = [line.strip() for line in expected_lines]

    assert actual_stripped == expected_stripped, (
        "The contents of cleaned_logs.txt do not match the expected output. "
        "Ensure corrupted archives are ignored, [DEBUG] lines are removed, "
        "and the final result is sorted alphabetically."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
