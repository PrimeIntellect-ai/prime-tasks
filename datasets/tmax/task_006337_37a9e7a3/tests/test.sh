#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_diagnostic_report_exists():
    report_path = "/home/user/diagnostic_report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist. The task is incomplete."
    assert os.path.isfile(report_path), f"{report_path} is not a regular file."

def test_diagnostic_report_contents():
    report_path = "/home/user/diagnostic_report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    expected_failing_query = "FAILING_QUERY: 45,99,0,12"
    expected_crash_signal = "CRASH_SIGNAL: SIGFPE"
    expected_crash_instruction = "CRASH_INSTRUCTION_MNEMONIC: idiv"

    assert any(expected_failing_query in line for line in lines), \
        f"Expected to find '{expected_failing_query}' in {report_path}"

    assert any(expected_crash_signal in line for line in lines), \
        f"Expected to find '{expected_crash_signal}' in {report_path}"

    assert any(expected_crash_instruction in line for line in lines), \
        f"Expected to find '{expected_crash_instruction}' in {report_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
