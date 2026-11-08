#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_incident_report_exists():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"The incident report file {report_path} does not exist."

def test_incident_report_contents():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"The incident report file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    expected_lines = {
        "BAD_COMMIT_MSG": "Refactor input validation logic",
        "RECOVERED_API_KEY": "API-9988-SECRET-KEY",
        "BINARY_PASSWORD": "NEXUS_CORE_0x9A",
        "CRASHING_PAYLOAD": "XQZQ"
    }

    parsed_report = {}
    for line in lines:
        if "=" in line:
            key, val = line.split("=", 1)
            parsed_report[key.strip()] = val.strip()

    for key, expected_val in expected_lines.items():
        assert key in parsed_report, f"Missing required key '{key}' in incident report."
        assert parsed_report[key] == expected_val, f"Incorrect value for '{key}'. Expected '{expected_val}', but got '{parsed_report[key]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
