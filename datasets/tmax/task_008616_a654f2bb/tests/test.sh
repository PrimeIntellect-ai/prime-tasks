#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def get_expected_bad_commit():
    result = subprocess.run(
        ["git", "log", "--format=%H", "--grep=Optimize parsing by assuming clean data"],
        cwd="/home/user/pipeline",
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()

def get_failing_line_number():
    with open("/home/user/sensor_data.csv", "r") as f:
        for i, line in enumerate(f, 1):
            if "N/A" in line:
                return i
    return -1

def test_diagnostic_report():
    report_path = "/home/user/diagnostic_report.txt"
    assert os.path.isfile(report_path), f"Diagnostic report missing at {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, f"Expected exactly 2 lines in diagnostic report, found {len(content)}"

    expected_commit = get_expected_bad_commit()
    expected_line = get_failing_line_number()

    assert expected_commit, "Could not determine expected bad commit from git history"
    assert expected_line > 0, "Could not determine expected failing line from sensor_data.csv"

    expected_line_1 = f"Bad Commit: {expected_commit}"
    expected_line_2 = f"Failing Line Number: {expected_line}"

    assert content[0].strip() == expected_line_1, f"First line is incorrect. Expected: '{expected_line_1}', Got: '{content[0]}'"
    assert content[1].strip() == expected_line_2, f"Second line is incorrect. Expected: '{expected_line_2}', Got: '{content[1]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
