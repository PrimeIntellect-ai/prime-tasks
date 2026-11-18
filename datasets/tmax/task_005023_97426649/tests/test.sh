#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_summary_file_exists():
    """Test that the summary.txt file was created at the correct location."""
    file_path = "/home/user/summary.txt"
    assert os.path.exists(file_path), f"Required file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_summary_file_content():
    """Test that the summary.txt file contains the correct gap-filled report."""
    file_path = "/home/user/summary.txt"

    expected_lines = [
        "[2023-11-01] STATUS: 2 events found. Max Crash Similarity: 1.0",
        "[2023-11-02] STATUS: MISSING. Max Crash Similarity: 0.00",
        "[2023-11-03] STATUS: 1 events found. Max Crash Similarity: 0.61",
        "[2023-11-04] STATUS: MISSING. Max Crash Similarity: 0.00",
        "[2023-11-05] STATUS: 1 events found. Max Crash Similarity: 0.24"
    ]

    expected_lines_alt = [
        "[2023-11-01] STATUS: 2 events found. Max Crash Similarity: 1.00",
        "[2023-11-02] STATUS: MISSING. Max Crash Similarity: 0.00",
        "[2023-11-03] STATUS: 1 events found. Max Crash Similarity: 0.61",
        "[2023-11-04] STATUS: MISSING. Max Crash Similarity: 0.00",
        "[2023-11-05] STATUS: 1 events found. Max Crash Similarity: 0.24"
    ]

    with open(file_path, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) == len(expected_lines), (
        f"Incorrect number of lines in {file_path}. "
        f"Expected {len(expected_lines)}, got {len(content)}."
    )

    for i in range(len(content)):
        assert content[i] in (expected_lines[i], expected_lines_alt[i]), (
            f"Line {i+1} mismatch in {file_path}.\n"
            f"Expected: {expected_lines_alt[i]}\n"
            f"Got:      {content[i]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
