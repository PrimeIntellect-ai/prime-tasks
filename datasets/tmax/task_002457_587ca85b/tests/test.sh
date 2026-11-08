#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

RESULT_PATH = '/home/user/top_hub.txt'

def test_result_file_exists():
    """Test that the expected result file has been created."""
    assert os.path.exists(RESULT_PATH), f"Result file not found at {RESULT_PATH}"
    assert os.path.isfile(RESULT_PATH), f"Path {RESULT_PATH} is not a regular file"

def test_result_file_content():
    """Test that the result file contains the correct node label."""
    assert os.path.exists(RESULT_PATH), f"Result file not found at {RESULT_PATH}"

    with open(RESULT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_label = "Sub_Hub_Alpha"
    assert content == expected_label, f"Expected '{expected_label}' but found '{content}' in {RESULT_PATH}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
