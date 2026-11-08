#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_influence_scores_file_exists():
    """Test that the output file exists in the correct location."""
    file_path = "/home/user/influence_scores.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

def test_influence_scores_content():
    """Test that the output file has the exact expected content and sorting."""
    file_path = "/home/user/influence_scores.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected_lines = [
        "user,influence_score",
        "Alice,2",
        "Bob,2",
        "Dave,2",
        "Charlie,1"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    assert content == expected_lines, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(content)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
