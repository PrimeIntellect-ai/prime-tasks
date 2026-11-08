#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

BAD_FILES_TXT = "/home/user/ticket_1029/bad_files.txt"
CORRECT_TOTAL_TXT = "/home/user/ticket_1029/correct_total.txt"

def test_bad_files_txt():
    """Test that bad_files.txt exists and contains the correct corrupted file names."""
    assert os.path.isfile(BAD_FILES_TXT), f"File {BAD_FILES_TXT} does not exist. Did you create it?"

    with open(BAD_FILES_TXT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["file_037.csv", "file_082.csv"]
    assert lines == expected_lines, f"Expected {expected_lines} in {BAD_FILES_TXT}, but found {lines}."

def test_correct_total_txt():
    """Test that correct_total.txt exists and contains the correct total sum."""
    assert os.path.isfile(CORRECT_TOTAL_TXT), f"File {CORRECT_TOTAL_TXT} does not exist. Did you compute and save the total?"

    with open(CORRECT_TOTAL_TXT, "r") as f:
        content = f.read().strip()

    expected_total = "10290.00"
    assert content == expected_total, f"Expected total {expected_total} in {CORRECT_TOTAL_TXT}, but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
