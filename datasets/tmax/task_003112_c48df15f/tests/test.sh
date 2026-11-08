#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_incident_report_exists_and_correct():
    """Test that the incident report exists and contains the correct findings."""
    report_path = "/home/user/incident_report.txt"

    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, but found {len(lines)}."

    expected_ip = "172.16.42.99"
    expected_exception = "RecursionError"

    assert lines[0] == expected_ip, f"Line 1: Expected '{expected_ip}', but got '{lines[0]}'."
    assert lines[1] == expected_exception, f"Line 2: Expected '{expected_exception}', but got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
