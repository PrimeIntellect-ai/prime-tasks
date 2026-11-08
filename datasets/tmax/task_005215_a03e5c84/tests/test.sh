#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_incident_report_exists_and_content():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"Report file not found at {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in the report, found {len(lines)}"

    expected_lines = [
        "SECRET_TOKEN=SRE_MONITOR_SECRET_992837465",
        "CRASH_UPTIME=16777216",
        "CRASH_FUNC=calculate_metrics"
    ]

    for expected, actual in zip(expected_lines, lines):
        assert actual == expected, f"Expected line '{expected}', but got '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
