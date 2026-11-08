#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_resolution_file_exists():
    """Check if the resolution file was created at the correct path."""
    assert os.path.isfile("/home/user/ticket_992_resolution.txt"), "The resolution file /home/user/ticket_992_resolution.txt is missing."

def test_resolution_file_content():
    """Check if the resolution file contains the correct epoch timestamp and decoded message."""
    expected_content = "1698825610 - ERROR: Corrupt magic bytes"

    with open("/home/user/ticket_992_resolution.txt", "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of the resolution file is incorrect. Expected: '{expected_content}', but got: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
