#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_compliance_report_exists():
    report_path = "/home/user/compliance_report.txt"
    assert os.path.isfile(report_path), f"Compliance report is missing at {report_path}"

def test_compliance_report_contents():
    report_path = "/home/user/compliance_report.txt"
    assert os.path.isfile(report_path), f"Compliance report is missing at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["log_01.txt", "log_03.txt"]

    assert lines == expected_lines, (
        f"Compliance report contents are incorrect. "
        f"Expected {expected_lines}, but got {lines}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
