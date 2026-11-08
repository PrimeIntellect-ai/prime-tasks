#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_overflow_report_exists():
    """Test that the overflow_report.csv file has been created."""
    assert os.path.isfile("/home/user/overflow_report.csv"), "The file /home/user/overflow_report.csv was not created."

def test_overflow_report_content():
    """Test that the overflow_report.csv file contains the correct violations sorted alphabetically."""
    expected_content = "fr,BTN_OK\nfr,MSG_ERROR\njp,BTN_OK"

    with open("/home/user/overflow_report.csv", "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of /home/user/overflow_report.csv is incorrect.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Got:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
