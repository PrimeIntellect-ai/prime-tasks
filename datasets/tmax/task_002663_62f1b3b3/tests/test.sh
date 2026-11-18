#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

EXPECTED_CSV_LINES = [
    "Hour,Message,Count",
    "2023-10-12_14,Base de données hors ligne,2",
    "2023-10-12_14,データベースエラー,2",
    "2023-10-12_15,Speicherplatz voll,2",
    "2023-10-12_15,データベースエラー,2",
    "2023-10-12_15,Connexion perdue,1",
    "2023-10-12_15,Disk full,1"
]

def test_error_summary_exists():
    assert os.path.isfile("/home/user/error_summary.csv"), "Output file /home/user/error_summary.csv was not created."

def test_error_summary_content():
    file_path = "/home/user/error_summary.csv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r", encoding="utf-8") as f:
        # Read lines and strip trailing whitespace/newlines
        actual_lines = [line.rstrip('\r\n') for line in f if line.strip()]

    assert len(actual_lines) > 0, f"File {file_path} is empty."

    assert actual_lines[0] == EXPECTED_CSV_LINES[0], f"Header mismatch. Expected '{EXPECTED_CSV_LINES[0]}', got '{actual_lines[0]}'"

    assert len(actual_lines) == len(EXPECTED_CSV_LINES), f"Expected {len(EXPECTED_CSV_LINES)} lines, but got {len(actual_lines)} lines."

    for i, (expected, actual) in enumerate(zip(EXPECTED_CSV_LINES, actual_lines)):
        assert actual == expected, f"Mismatch at line {i + 1}. Expected '{expected}', got '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
