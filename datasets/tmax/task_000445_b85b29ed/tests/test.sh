#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_incident_report_exists():
    assert os.path.isfile("/home/user/incident_report.txt"), "The file /home/user/incident_report.txt does not exist."

def test_incident_report_contents():
    with open("/home/user/incident_report.txt", "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in /home/user/incident_report.txt, but found {len(lines)}."

    expected_timestamp = "2023-11-05T14:22:04Z"
    expected_password = "Tr0ub4dor&3"

    assert lines[0].strip() == expected_timestamp, f"Line 1 is incorrect. Expected '{expected_timestamp}', got '{lines[0]}'."
    assert lines[1].strip() == expected_password, f"Line 2 is incorrect. Expected '{expected_password}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
