#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_compromised_user_file():
    """Test that the compromised_user.txt file exists and contains the correct username."""
    expected_file = "/home/user/compromised_user.txt"

    assert os.path.exists(expected_file), f"Verification Failed: {expected_file} does not exist."
    assert os.path.isfile(expected_file), f"Verification Failed: {expected_file} is not a file."

    with open(expected_file, "r") as f:
        content = f.read()

    # The task specifies: "Ensure your final output file contains only the exact username string with no extra spaces or newline characters."
    # We will strip newlines and carriage returns just in case the user added a trailing newline, 
    # but strictly speaking, we check the exact content or stripped content as per the bash verification script.
    # The bash script does: RESULT=$(cat "$OUTPUT_FILE" | tr -d '\n' | tr -d '\r')

    result = content.replace("\n", "").replace("\r", "").strip()
    expected = "backup_svc"

    assert result == expected, f"Verification Failed: Expected '{expected}', got '{result}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
