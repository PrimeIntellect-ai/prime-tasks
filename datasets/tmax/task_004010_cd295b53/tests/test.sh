#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_forensics_report_exists():
    path = "/home/user/forensics_report.txt"
    assert os.path.isfile(path), f"The file {path} does not exist. You need to create it."

def test_forensics_report_contents():
    path = "/home/user/forensics_report.txt"
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, but found {len(lines)}."

    expected_salt = "SALT: X9k2#mP"
    expected_token = "TOKEN: USER-84729-ADMIN"

    assert lines[0] == expected_salt, f"Line 1 is incorrect. Expected '{expected_salt}', got '{lines[0]}'."
    assert lines[1] == expected_token, f"Line 2 is incorrect. Expected '{expected_token}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
