#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_leak_report_exists_and_correct():
    report_path = "/home/user/leak_report.txt"

    assert os.path.exists(report_path), f"The output file {report_path} was not created."
    assert os.path.isfile(report_path), f"The path {report_path} is not a regular file."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "PID: 1088, LEAK_MB: 250"

    assert content == expected_content, (
        f"The content of {report_path} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
