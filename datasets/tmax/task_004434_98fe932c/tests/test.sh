#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_exists():
    report_path = "/home/user/investigation/report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} is missing."

def test_report_content():
    report_path = "/home/user/investigation/report.txt"
    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "Password: byte\nAttacker IP: 172.16.0.88"

    assert content == expected_content, (
        f"The contents of {report_path} do not match the expected format or values.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
