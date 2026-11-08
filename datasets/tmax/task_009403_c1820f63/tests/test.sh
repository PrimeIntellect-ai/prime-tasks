#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

REPORT_FILE = "/home/user/deadlock_report.txt"
EXPECTED_OUTPUT = "T104,T105,T106"

def test_deadlock_report_exists():
    """Check that the deadlock report file was created."""
    assert os.path.exists(REPORT_FILE), f"The file {REPORT_FILE} does not exist. Did you create it?"
    assert os.path.isfile(REPORT_FILE), f"{REPORT_FILE} is not a regular file."

def test_deadlock_report_content():
    """Verify that the deadlock report contains the correct 3-cycle transaction IDs."""
    assert os.path.exists(REPORT_FILE), f"Cannot check content because {REPORT_FILE} does not exist."

    with open(REPORT_FILE, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_OUTPUT, (
        f"Incorrect deadlock report content.\n"
        f"Expected: '{EXPECTED_OUTPUT}'\n"
        f"Found: '{content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
