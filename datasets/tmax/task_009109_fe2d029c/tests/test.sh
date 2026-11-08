#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_deadlocks_csv_exists_and_content():
    file_path = "/home/user/deadlocks.csv"

    # Check if the file exists
    assert os.path.isfile(file_path), f"The file {file_path} does not exist. Did you create it?"

    expected_lines = [
        "deadlocked_tx_id",
        "1",
        "2",
        "3",
        "7",
        "8",
        "9",
        "11"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {file_path} is incorrect.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
